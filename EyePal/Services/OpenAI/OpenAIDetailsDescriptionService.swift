import Foundation
import UIKit

struct DetailsDescriptionTurn: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

enum OpenAIDetailsDescriptionError: LocalizedError {
    case missingImage
    case invalidResponse
    case emptyResponse
    case unauthorized
    case backendError(String)

    var errorDescription: String? {
        switch self {
        case .missingImage:
            return "Take a photo before asking for a description."
        case .invalidResponse:
            return "The OpenAI response could not be read."
        case .emptyResponse:
            return "OpenAI returned an empty description."
        case .unauthorized:
            return "Your ChatGPT sign-in expired. Sign in again."
        case .backendError(let message):
            return message
        }
    }
}

final class OpenAIDetailsDescriptionService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepareImageData(from image: UIImage) throws -> Data {
        let maximumDimension: CGFloat = 768
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else {
            throw OpenAIDetailsDescriptionError.missingImage
        }

        let scale = min(1, maximumDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.72) else {
            throw OpenAIDetailsDescriptionError.invalidResponse
        }

        return jpegData
    }

    func generateResponse(
        imageData: Data,
        conversation: [DetailsDescriptionTurn],
        store: OpenAISubscriptionStore
    ) async throws -> String {
        try await performRequest(
            imageData: imageData,
            conversation: conversation,
            store: store,
            retryOnUnauthorized: true
        )
    }

    private func performRequest(
        imageData: Data,
        conversation: [DetailsDescriptionTurn],
        store: OpenAISubscriptionStore,
        retryOnUnauthorized: Bool
    ) async throws -> String {
        let credentials = try await store.activeCredentials(forceRefresh: false)
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("EyePal/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let body = makePayload(imageData: imageData, conversation: conversation)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIDetailsDescriptionError.invalidResponse
        }

        if httpResponse.statusCode == 401 && retryOnUnauthorized {
            _ = try await store.activeCredentials(forceRefresh: true)
            return try await performRequest(
                imageData: imageData,
                conversation: conversation,
                store: store,
                retryOnUnauthorized: false
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw OpenAIDetailsDescriptionError.unauthorized
            }

            if let backendError = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data) {
                throw OpenAIDetailsDescriptionError.backendError(backendError.error.message)
            }

            let fallback = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw OpenAIDetailsDescriptionError.backendError(fallback)
        }

        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard let text = envelope.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw OpenAIDetailsDescriptionError.emptyResponse
        }

        return text
    }

    private func makePayload(imageData: Data, conversation: [DetailsDescriptionTurn]) -> [String: Any] {
        [
            "model": "gpt-5.4",
            "instructions": makeInstructions(),
            "store": false,
            "stream": false,
            "input": buildInput(from: conversation, imageData: imageData)
        ]
    }

    private func makeInstructions() -> String {
        let baseInstructions = "You are a concise visual assistant for a blind user. Describe the scene accurately, prioritize safety-relevant details, visible text, people, objects, layout, and orientation cues. Answer follow-up questions using the image and prior conversation."

        guard let systemLanguageInstruction = currentSystemLanguageInstruction() else {
            return baseInstructions
        }

        return "\(baseInstructions) \(systemLanguageInstruction)"
    }

    private func currentSystemLanguageInstruction() -> String? {
        guard let preferredLanguageIdentifier = Locale.preferredLanguages.first,
              !preferredLanguageIdentifier.isEmpty else {
            return nil
        }

        let localizedLanguageName = Locale.current.localizedString(forIdentifier: preferredLanguageIdentifier)
            ?? Locale(identifier: "en").localizedString(forIdentifier: preferredLanguageIdentifier)

        if let localizedLanguageName, !localizedLanguageName.isEmpty {
            return "Use the user's current system language for your response: \(localizedLanguageName) (\(preferredLanguageIdentifier))."
        }

        return "Use the user's current system language for your response: \(preferredLanguageIdentifier)."
    }

    private func buildInput(from conversation: [DetailsDescriptionTurn], imageData: Data) -> [[String: Any]] {
        let imageItem: [String: Any] = [
            "type": "input_image",
            "image_url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        ]

        guard let firstTurn = conversation.first else {
            return []
        }

        var input = [[String: Any]]()
        input.append([
            "role": firstTurn.role.rawValue,
            "content": [
                ["type": "input_text", "text": firstTurn.text],
                imageItem
            ]
        ])

        for turn in conversation.dropFirst() {
            input.append([
                "role": turn.role.rawValue,
                "content": [
                    [
                        "type": "input_text",
                        "text": turn.text
                    ]
                ]
            ])
        }

        return input
    }
}

private struct BackendErrorEnvelope: Decodable {
    struct ErrorBody: Decodable {
        let message: String
    }

    let error: ErrorBody
}

private struct ResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let text: String?
        }

        let content: [ContentItem]?
    }

    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var primaryText: String? {
        if let outputText, !outputText.isEmpty {
            return outputText
        }

        return output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
}
