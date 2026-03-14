import AVFoundation
import Foundation

@MainActor
final class FaceRecognitionViewModel: ObservableObject {
    @Published var statusText = "Point the camera at a face."
    @Published var recognizedName: String?
    @Published var pendingSuggestion: FaceSuggestion?
    @Published var profiles: [FaceProfile] = []
    @Published var errorMessage: String?

    let camera = CameraPipeline()

    private let recognitionService = FaceRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?

    init() {
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
        recognitionService.recognitionThreshold = settings.faceMatchThreshold
    }

    func start() {
        statusText = "Starting face recognition."
        camera.start()

        Task {
            do {
                profiles = try await recognitionService.loadProfiles()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        camera.stop()
    }

    func saveSuggestion(named name: String) {
        guard let pendingSuggestion else { return }

        Task {
            do {
                profiles = try await recognitionService.saveFace(name: name, suggestion: pendingSuggestion)
                self.pendingSuggestion = nil
                statusText = "\(name) was saved for on-device recognition."
                announcer.announce(statusText, minimumInterval: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func dismissSuggestion() {
        pendingSuggestion = nil
    }

    func deleteProfile(id: UUID) {
        Task {
            do {
                profiles = try await recognitionService.deleteProfile(id: id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        recognitionService.process(sampleBuffer: sampleBuffer) { [weak self] match, suggestion in
            guard let self else { return }

            if let match {
                recognizedName = match.name
                statusText = "Recognized \(match.name)."
                announcer.announce(match.name, minimumInterval: settingsStore?.speechCooldown ?? 2.5)
            } else {
                recognizedName = nil
                statusText = "Scanning for known faces."
            }

            if let suggestion, pendingSuggestion == nil, settingsStore?.suggestUnknownFaces ?? true {
                pendingSuggestion = suggestion
                announcer.announce("Unknown face detected. You can add this person.", minimumInterval: 3)
            }
        }
    }
}