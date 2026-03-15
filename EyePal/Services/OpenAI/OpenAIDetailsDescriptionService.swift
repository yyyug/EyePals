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
        let maximumDimension: CGFloat = 640
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
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("EyePal/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let body = makePayload(imageData: imageData, conversation: conversation)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
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
            let data = try await collectData(from: bytes)
            if httpResponse.statusCode == 401 {
                throw OpenAIDetailsDescriptionError.unauthorized
            }

            if let backendError = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data) {
                throw OpenAIDetailsDescriptionError.backendError(backendError.error.message)
            }

            let fallback = String(data: data, encoding: .utf8) ?? "HTTP \(httpResponse.statusCode)"
            throw OpenAIDetailsDescriptionError.backendError(fallback)
        }

        if let streamedText = try await readStreamedResponse(from: bytes) {
            return streamedText
        }

        throw OpenAIDetailsDescriptionError.emptyResponse
    }

    private func makePayload(imageData: Data, conversation: [DetailsDescriptionTurn]) -> [String: Any] {
        [
            "model": "gpt-5.1-codex-mini",
            "instructions": makeInstructions(),
            "store": false,
            "stream": true,
            "input": buildInput(from: conversation, imageData: imageData)
        ]
    }

    private func readStreamedResponse(from bytes: URLSession.AsyncBytes) async throws -> String? {
        var streamedText = ""
        var rawEventData = Data()
        var streamedErrorMessage: String?

        for try await line in bytes.lines {
            if line.isEmpty {
                continue
            }

            let payloadLine: String
            if line == "data: [DONE]" || line == "[DONE]" {
                break
            } else if line.hasPrefix("data: ") {
                payloadLine = String(line.dropFirst(6))
            } else {
                payloadLine = line
            }

            guard let lineData = payloadLine.data(using: .utf8) else {
                continue
            }

            rawEventData.append(lineData)
            rawEventData.append(0x0A)

            if let errorMessage = extractErrorMessage(from: lineData) {
                streamedErrorMessage = errorMessage
            }

            if let chunk = extractTextChunk(from: lineData) {
                streamedText += chunk
            }
        }

        if let streamedErrorMessage, streamedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OpenAIDetailsDescriptionError.backendError(streamedErrorMessage)
        }

        let trimmedStreamedText = streamedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStreamedText.isEmpty {
            return trimmedStreamedText
        }

        if let bufferedErrorMessage = extractErrorMessage(from: rawEventData) {
            throw OpenAIDetailsDescriptionError.backendError(bufferedErrorMessage)
        }

        if let bufferedText = extractBufferedText(from: rawEventData) {
            return bufferedText
        }

        return nil
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func extractBufferedText(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(ResponseEnvelope.self, from: data),
           let text = envelope.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }

        let jsonLines = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let lineData = trimmedLine.data(using: .utf8) else { return nil }
                return extractTextChunk(from: lineData)
            } ?? []

        let combined = jsonLines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private func extractTextChunk(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return extractTextChunk(from: object)
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data) {
            return envelope.error.message
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        return extractErrorMessage(from: object)
    }

    private func extractTextChunk(from object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let delta = dictionary["delta"] as? String, !delta.isEmpty {
                return delta
            }

            if let outputText = dictionary["output_text"] as? String, !outputText.isEmpty {
                return outputText
            }

            if let text = dictionary["text"] as? String,
               let type = dictionary["type"] as? String,
               type.localizedCaseInsensitiveContains("text") {
                return text
            }

            for value in dictionary.values {
                if let nestedText = extractTextChunk(from: value) {
                    return nestedText
                }
            }

            return nil
        }

        if let array = object as? [Any] {
            for value in array {
                if let nestedText = extractTextChunk(from: value) {
                    return nestedText
                }
            }
        }

        return nil
    }

    private func extractErrorMessage(from object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let error = dictionary["error"] as? [String: Any],
               let message = error["message"] as? String,
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }

            if let detail = dictionary["detail"] as? String,
               !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return detail
            }

            if let message = dictionary["message"] as? String,
               let type = dictionary["type"] as? String,
               type.localizedCaseInsensitiveContains("error"),
               !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return message
            }

            for value in dictionary.values {
                if let nestedMessage = extractErrorMessage(from: value) {
                    return nestedMessage
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let nestedMessage = extractErrorMessage(from: value) {
                    return nestedMessage
                }
            }
        }

        return nil
    }

    private func makeInstructions() -> String {
        let baseInstructions = "You are a concise visual assistant for a blind user. Describe the scene accurately, prioritize safety-relevant details, visible text, people, objects, layout, and orientation cues. Answer follow-up questions using the image and prior conversation. Do not use markdown bold formatting or surround words with double asterisks."

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
            let content: [[String: Any]]
            if turn.role == .assistant {
                content = [[
                    "type": "output_text",
                    "text": turn.text,
                    "phase": "final_answer"
                ]]
            } else {
                content = [[
                    "type": "input_text",
                    "text": turn.text
                ]]
            }

            input.append([
                "role": turn.role.rawValue,
                "content": content
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
