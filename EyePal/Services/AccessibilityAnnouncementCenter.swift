import UIKit

@MainActor
final class AccessibilityAnnouncementCenter {
    private var lastAnnouncement = ""
    private var lastAnnouncementDate = Date.distantPast

    func announce(_ text: String, minimumInterval: TimeInterval) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let now = Date()
        guard now.timeIntervalSince(lastAnnouncementDate) >= minimumInterval else {
            return
        }

        guard trimmed != lastAnnouncement || minimumInterval == 0 else {
            return
        }

        lastAnnouncement = trimmed
        lastAnnouncementDate = now
        UIAccessibility.post(notification: .announcement, argument: trimmed)
    }
}
