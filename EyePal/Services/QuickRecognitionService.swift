import Foundation
import UIKit

enum QuickRecognitionError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case emptyResponse
    case badStatusCode(Int, String)
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Add your Moondream API key in Settings > Quick Recognition."
        case .invalidURL:
            return "The Moondream API URL is invalid."
        case .invalidResponse:
            return "The Moondream response could not be read."
        case .emptyResponse:
            return "Moondream returned an empty response."
        case .badStatusCode(let code, let body):
            return body.isEmpty ? "Moondream request failed with HTTP \(code)." : body
        case .imageEncodingFailed:
            return "The image could not be prepared for quick recognition."
        }
    }
}

final class QuickRecognitionService {
    private let session: URLSession
    private let baseURL = "https://api.moondream.ai/v1"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepareImageDataURL(from image: UIImage) throws -> String {
        let maximumDimension: CGFloat = 320
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else {
            throw QuickRecognitionError.imageEncodingFailed
        }

        let scale = min(1, maximumDimension / max(originalSize.width, originalSize.height))
        let targetSize = CGSize(width: originalSize.width * scale, height: originalSize.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.5) else {
            throw QuickRecognitionError.imageEncodingFailed
        }

        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    func generateCaption(
        imageDataURL: String,
        length: QuickCaptionLength,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickRecognitionError.missingAPIKey
        }

        let payload: [String: Any] = [
            "image_url": imageDataURL,
            "length": length.rawValue
        ]

        let response = try await performRequest(
            path: "/caption",
            payload: payload,
            apiKey: apiKey
        )

        guard let caption = response["caption"] as? String else {
            throw QuickRecognitionError.invalidResponse
        }

        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuickRecognitionError.emptyResponse
        }
        return trimmed
    }

    func queryImage(
        imageDataURL: String,
        question: String,
        enforceSingleSentenceResponse: Bool,
        apiKey: String
    ) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuickRecognitionError.missingAPIKey
        }

        let formattedQuestion = enforceSingleSentenceResponse
            ? question + " respond with one sentence"
            : question

        let payload: [String: Any] = [
            "image_url": imageDataURL,
            "question": formattedQuestion
        ]

        let response = try await performRequest(
            path: "/query",
            payload: payload,
            apiKey: apiKey
        )

        guard let answer = response["answer"] as? String else {
            throw QuickRecognitionError.invalidResponse
        }

        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw QuickRecognitionError.emptyResponse
        }
        return trimmed
    }

    private func performRequest(
        path: String,
        payload: [String: Any],
        apiKey: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else {
            throw QuickRecognitionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Moondream-Auth")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QuickRecognitionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw QuickRecognitionError.badStatusCode(httpResponse.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuickRecognitionError.invalidResponse
        }

        return json
    }
}
