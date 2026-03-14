import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("speechCooldown") var speechCooldown = 2.5
    @AppStorage("faceMatchThreshold") var faceMatchThreshold = 0.87
    @AppStorage("suggestUnknownFaces") var suggestUnknownFaces = true
    @AppStorage("quickMoondreamAPIKey") var quickMoondreamAPIKey = ""
    @AppStorage("quickCaptionLength") var quickCaptionLength = QuickCaptionLength.short.rawValue
    @AppStorage("quickContinuousCaptureInterval") var quickContinuousCaptureInterval = QuickContinuousCaptureInterval.defaultInterval.rawValue
    @AppStorage("quickCaptionTranslationEnabled") var quickCaptionTranslationEnabled = false
    @AppStorage("quickCaptionTranslationTargetLanguage") var quickCaptionTranslationTargetLanguage = ""
    @AppStorage("quickCustomQueryTitle") var quickCustomQueryTitle = QuickCustomQueryPreset.defaultTitle
    @AppStorage("quickCustomQueryPrompt") var quickCustomQueryPrompt = QuickCustomQueryPreset.defaultPrompt
}
