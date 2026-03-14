import AVFoundation
import CoreImage
import UIKit
import Vision

struct FaceMatch: Equatable {
    let name: String
    let confidence: Float
}

final class FaceRecognitionService {
    private struct CandidateMatch {
        let profile: FaceProfile
        let confidence: Float
    }

    private let embeddingEngine = FaceEmbeddingEngine()
    private let faceStore = FaceStore()
    private let processingQueue = DispatchQueue(label: "com.eyepals.face.recognition")
    private let context = CIContext()

    private var isProcessing = false
    private var profiles: [FaceProfile] = []
    private var lastUnknownSuggestionDate = Date.distantPast
    private var consecutiveUnknownFrames = 0
    private var pendingKnownMatch: CandidateMatch?
    private var consecutiveKnownFrames = 0

    var recognitionThreshold: Float = 0.87
    var suggestionFrameThreshold = 6
    var minimumSuggestionInterval: TimeInterval = 10
    var knownMatchFrameThreshold = 2
    var minimumTopMatchMargin: Float = 0.015

    func loadProfiles() async throws -> [FaceProfile] {
        let loaded = try await faceStore.loadProfiles()
        profiles = loaded
        return loaded
    }

    func process(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping @MainActor (FaceMatch?, FaceSuggestion?) -> Void
    ) {
        processingQueue.async {
            guard !self.isProcessing else { return }
            self.isProcessing = true

            Task {
                defer {
                    self.processingQueue.async {
                        self.isProcessing = false
                    }
                }

                do {
                    let faceImage = try self.extractPrimaryFace(from: sampleBuffer)
                    let embedding = try await self.embeddingEngine.embedding(for: faceImage)

                    if let match = self.confirmedMatch(for: embedding) {
                        self.consecutiveUnknownFrames = 0
                        await completion(match, nil)
                    } else {
                        let suggestion = self.handleUnknownFace(embedding: embedding, faceImage: faceImage)
                        await completion(nil, suggestion)
                    }
                } catch {
                    await completion(nil, nil)
                }
            }
        }
    }

    func saveFace(name: String, suggestion: FaceSuggestion) async throws -> [FaceProfile] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return profiles }

        var profile = FaceProfile(name: trimmedName, embedding: suggestion.embedding)
        if let jpegData = suggestion.jpegData {
            profile.sampleImageFilename = try await faceStore.saveImage(jpegData, for: profile.id)
        }
        profiles.append(profile)
        try await faceStore.saveProfiles(profiles)
        return profiles
    }

    func deleteProfile(id: UUID) async throws -> [FaceProfile] {
        profiles.removeAll { $0.id == id }
        try await faceStore.saveProfiles(profiles)
        return profiles
    }

    private func extractPrimaryFace(from sampleBuffer: CMSampleBuffer) throws -> CGImage {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw FaceEmbeddingError.invalidOutput
        }

        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try handler.perform([request])

        guard let observation = (request.results as? [VNFaceObservation])?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            throw FaceEmbeddingError.invalidOutput
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let imageRect = ciImage.extent
        let cropRect = VNImageRectForNormalizedRect(observation.boundingBox, Int(imageRect.width), Int(imageRect.height))
            .insetBy(dx: -24, dy: -24)
            .intersection(imageRect)

        let cropped = ciImage.cropped(to: cropRect)
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
            throw FaceEmbeddingError.invalidOutput
        }

        return cgImage
    }

    private func confirmedMatch(for embedding: [Float]) -> FaceMatch? {
        guard let candidate = bestMatch(for: embedding) else {
            pendingKnownMatch = nil
            consecutiveKnownFrames = 0
            return nil
        }

        if pendingKnownMatch?.profile.id == candidate.profile.id {
            consecutiveKnownFrames += 1
            pendingKnownMatch = candidate
        } else {
            pendingKnownMatch = candidate
            consecutiveKnownFrames = 1
        }

        guard consecutiveKnownFrames >= knownMatchFrameThreshold else {
            return nil
        }

        return FaceMatch(name: candidate.profile.name, confidence: candidate.confidence)
    }

    private func bestMatch(for embedding: [Float]) -> CandidateMatch? {
        let rankedCandidates = profiles
            .map { profile in
                CandidateMatch(profile: profile, confidence: cosineSimilarity(embedding, profile.embedding))
            }
            .sorted { $0.confidence > $1.confidence }

        guard let bestCandidate = rankedCandidates.first,
              bestCandidate.confidence >= recognitionThreshold else {
            return nil
        }

        if rankedCandidates.count > 1 {
            let secondBestConfidence = rankedCandidates[1].confidence
            guard (bestCandidate.confidence - secondBestConfidence) >= minimumTopMatchMargin else {
                return nil
            }
        }

        guard bestCandidate.confidence >= recognitionThreshold else {
            return nil
        }

        return bestCandidate
    }

    private func handleUnknownFace(embedding: [Float], faceImage: CGImage) -> FaceSuggestion? {
        pendingKnownMatch = nil
        consecutiveKnownFrames = 0
        consecutiveUnknownFrames += 1

        guard consecutiveUnknownFrames >= suggestionFrameThreshold else {
            return nil
        }

        let now = Date()
        guard now.timeIntervalSince(lastUnknownSuggestionDate) >= minimumSuggestionInterval else {
            return nil
        }

        lastUnknownSuggestionDate = now
        consecutiveUnknownFrames = 0

        let jpegData = UIImage(cgImage: faceImage).jpegData(compressionQuality: 0.8)
        return FaceSuggestion(embedding: embedding, jpegData: jpegData)
    }
}

private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count, !lhs.isEmpty else { return -1 }
    return zip(lhs, rhs).reduce(0) { $0 + ($1.0 * $1.1) }
}
