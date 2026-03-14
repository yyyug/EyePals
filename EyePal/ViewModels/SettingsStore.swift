import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("speechCooldown") var speechCooldown = 2.5
    @AppStorage("faceMatchThreshold") var faceMatchThreshold = 0.9
    @AppStorage("suggestUnknownFaces") var suggestUnknownFaces = true
}
