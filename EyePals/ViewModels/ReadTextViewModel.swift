import AVFoundation
import Foundation

@MainActor
final class ReadTextViewModel: ObservableObject {
    @Published var recognizedText = "Point the camera at printed text."
    @Published var detectedLanguage = "Unknown"
    @Published var cameraStateDescription = "Preparing camera..."

    let camera = CameraPipeline()

    private let textRecognitionService = TextRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?

    init() {
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
    }

    func start() {
        cameraStateDescription = "Starting live text reader."
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        textRecognitionService.process(sampleBuffer: sampleBuffer) { [weak self] observation in
            guard let self, let observation else { return }

            self.recognizedText = observation.text
            self.detectedLanguage = observation.languageCode ?? "Unknown"
            self.cameraStateDescription = "Reading live text."

            let minimumInterval = self.settingsStore?.speechCooldown ?? 2.5
            self.announcer.announce(observation.text, minimumInterval: minimumInterval)
        }
    }
}