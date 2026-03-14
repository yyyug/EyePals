import SwiftUI

@main
struct EyePalsApp: App {
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settingsStore)
        }
    }
}