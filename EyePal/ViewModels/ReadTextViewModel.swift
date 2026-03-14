import AVFoundation
import Foundation
import UIKit

@MainActor
final class ReadTextViewModel: ObservableObject {
    struct CapturedTextResult: Identifiable {
        let id = UUID()
        let text: String
        let language: String
    }

    @Published var recognizedText = "Point the camera at printed text."
    @Published var detectedLanguage = "Unknown"
    @Published var cameraStateDescription = "Preparing camera..."
    @Published var capturedResult: CapturedTextResult?
    @Published var isCapturingPhoto = false

    let camera = CameraPipeline()

    private let textRecognitionService = TextRecognitionService()
    private let announcer = AccessibilityAnnouncementCenter()
    private weak var settingsStore: SettingsStore?
    private let stabilityInterval: TimeInterval = 0.6
    private let minimumStableRepeats = 2
    private let meaningfulChangeThreshold = 0.85

    private var pendingAnnouncementText = ""
    private var pendingAnnouncementSpokenText = ""
    private var pendingAnnouncementLanguage = "Unknown"
    private var pendingAnnouncementDate = Date.distantPast
    private var pendingAnnouncementCount = 0
    private var lastSpokenNormalizedText = ""
    private var isPresentingCapturedResult = false

    init() {
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            self?.handle(sampleBuffer: sampleBuffer)
        }
    }

    func bind(settings: SettingsStore) {
        settingsStore = settings
    }

    func start() {
        guard !isPresentingCapturedResult else { return }
        cameraStateDescription = "Starting live text reader."
        camera.start()
    }

    func stop() {
        camera.stop()
    }

    func capturePhoto() {
        guard !isCapturingPhoto else { return }
        guard let image = camera.currentFrameImage() else {
            cameraStateDescription = "No camera frame is ready yet."
            return
        }

        isCapturingPhoto = true
        isPresentingCapturedResult = true
        camera.stop()
        cameraStateDescription = "Reading captured photo."

        textRecognitionService.process(image: image) { [weak self] observation in
            guard let self else { return }

            let text = observation?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.capturedResult = CapturedTextResult(
                text: text?.isEmpty == false ? text! : "No text was found in this photo.",
                language: observation?.languageCode ?? "Unknown"
            )
            self.isCapturingPhoto = false
            self.cameraStateDescription = "Captured text is ready."
        }
    }

    func dismissCapturedResult() {
        capturedResult = nil
        isPresentingCapturedResult = false
        pendingAnnouncementText = ""
        pendingAnnouncementSpokenText = ""
        pendingAnnouncementCount = 0
        cameraStateDescription = "Starting live text reader."
        camera.start()
    }

    private func handle(sampleBuffer: CMSampleBuffer) {
        guard !isPresentingCapturedResult else { return }

        textRecognitionService.process(sampleBuffer: sampleBuffer) { [weak self] observation in
            guard let self, let observation else { return }

            self.recognizedText = observation.text
            self.detectedLanguage = observation.languageCode ?? "Unknown"
            self.cameraStateDescription = "Reading live text."
            self.handleLiveObservation(observation)
        }
    }

    private func handleLiveObservation(_ observation: TextRecognitionObservation) {
        let normalizedText = normalizeForAnnouncement(observation.text)
        guard !normalizedText.isEmpty else { return }

        let now = Date()
        if pendingAnnouncementText.isEmpty {
            pendingAnnouncementText = normalizedText
            pendingAnnouncementSpokenText = observation.text
            pendingAnnouncementLanguage = observation.languageCode ?? "Unknown"
            pendingAnnouncementDate = now
            pendingAnnouncementCount = 1
            return
        }

        let candidateSimilarity = similarity(between: normalizedText, and: pendingAnnouncementText)
        if candidateSimilarity >= meaningfulChangeThreshold {
            pendingAnnouncementCount += 1
            pendingAnnouncementSpokenText = preferredAnnouncementText(current: pendingAnnouncementSpokenText, replacement: observation.text)
            pendingAnnouncementLanguage = observation.languageCode ?? pendingAnnouncementLanguage
        } else {
            pendingAnnouncementText = normalizedText
            pendingAnnouncementSpokenText = observation.text
            pendingAnnouncementLanguage = observation.languageCode ?? "Unknown"
            pendingAnnouncementDate = now
            pendingAnnouncementCount = 1
            return
        }

        let isStable = pendingAnnouncementCount >= minimumStableRepeats
            || now.timeIntervalSince(pendingAnnouncementDate) >= stabilityInterval
        guard isStable else { return }

        guard lastSpokenNormalizedText.isEmpty
            || similarity(between: pendingAnnouncementText, and: lastSpokenNormalizedText) < meaningfulChangeThreshold else {
            return
        }

        lastSpokenNormalizedText = pendingAnnouncementText
        detectedLanguage = pendingAnnouncementLanguage
        announcer.announce(pendingAnnouncementSpokenText, minimumInterval: settingsStore?.speechCooldown ?? 2.5)
    }

    private func normalizeForAnnouncement(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func preferredAnnouncementText(current: String, replacement: String) -> String {
        replacement.count >= current.count ? replacement : current
    }

    private func similarity(between lhs: String, and rhs: String) -> Double {
        let left = String(lhs.prefix(280))
        let right = String(rhs.prefix(280))

        guard !left.isEmpty || !right.isEmpty else { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let distance = levenshteinDistance(Array(left), Array(right))
        return 1 - (Double(distance) / Double(max(left.count, right.count)))
    }

    private func levenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)

        for (leftIndex, leftCharacter) in lhs.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(rhs.count + 1)

            for (rightIndex, rightCharacter) in rhs.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }

            previous = current
        }

        return previous[rhs.count]
    }
}
