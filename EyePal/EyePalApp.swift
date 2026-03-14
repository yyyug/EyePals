import SwiftUI

@main
struct EyePalApp: App {
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var openAIStore = OpenAISubscriptionStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settingsStore)
                .environmentObject(openAIStore)
        }
    }
}
