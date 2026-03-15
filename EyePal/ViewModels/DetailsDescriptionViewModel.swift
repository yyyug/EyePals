import Foundation
import UIKit

@MainActor
final class DetailsDescriptionViewModel: ObservableObject {
    private static let helperInstruction = "Take a photo to describe the scene."

    @Published var statusText = helperInstruction
    @Published var descriptionText = ""
    @Published var followUpQuestion = ""
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var capturedPreview: UIImage?

    let camera = CameraPipeline()

    private let descriptionService = OpenAIDetailsDescriptionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private var conversation: [DetailsDescriptionTurn] = []
    private var imageData: Data?
    private var openAIStore: OpenAISubscriptionStore?

    func bind(openAIStore: OpenAISubscriptionStore) {
        self.openAIStore = openAIStore
    }

    func start() {
        statusText = Self.helperInstruction
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    func capturePhoto() {
        guard !isProcessing else { return }
        guard let openAIStore else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            return
        }
        guard openAIStore.isSignedIn else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            return
        }
        guard let image = camera.currentFrameImage() else {
            statusText = "No camera frame is ready yet."
            return
        }

        isProcessing = true
        statusText = "Describing the photo."
        camera.stop()
        capturedPreview = image

        Task {
            do {
                let preparedImageData = try descriptionService.prepareImageData(from: image)
                imageData = preparedImageData
                conversation = [
                    DetailsDescriptionTurn(
                        role: .user,
                        text: "Describe this image for a blind user. Focus on people, objects, visible text, layout, hazards, and orientation cues. Be concise but specific. Do not use markdown or double asterisks."
                    )
                ]

                let response = try await descriptionService.generateResponse(
                    imageData: preparedImageData,
                    conversation: conversation,
                    store: openAIStore
                )

                conversation.append(DetailsDescriptionTurn(role: .assistant, text: response))
                descriptionText = response
                statusText = "Photo details are ready."
                announcer.announce(response, minimumInterval: 0)
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Could not describe the photo."
                isProcessing = false
            }
        }
    }

    func submitFollowUp() {
        guard !isProcessing else { return }
        guard let openAIStore else {
            errorMessage = OpenAISubscriptionError.notSignedIn.localizedDescription
            return
        }
        guard let imageData else {
            errorMessage = OpenAIDetailsDescriptionError.missingImage.localizedDescription
            return
        }

        let question = followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        isProcessing = true
        statusText = "Asking a follow-up question."
        conversation.append(DetailsDescriptionTurn(role: .user, text: question))
        followUpQuestion = ""

        Task {
            do {
                let response = try await descriptionService.generateResponse(
                    imageData: imageData,
                    conversation: conversation,
                    store: openAIStore
                )

                conversation.append(DetailsDescriptionTurn(role: .assistant, text: response))
                descriptionText = response
                statusText = "Follow-up answer is ready."
                announcer.announce(response, minimumInterval: 0)
                isProcessing = false
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Could not answer the follow-up question."
                isProcessing = false
            }
        }
    }

    func retake() {
        isProcessing = false
        descriptionText = ""
        followUpQuestion = ""
        conversation = []
        imageData = nil
        capturedPreview = nil
        errorMessage = nil
        statusText = Self.helperInstruction
        camera.start()
    }
}
