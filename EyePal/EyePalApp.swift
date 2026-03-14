import SwiftUI

@main
struct EyePalApp: App {
    @StateObject private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settingsStore)
        }
    }
}
