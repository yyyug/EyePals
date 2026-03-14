import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            ReadTextView()
                .tabItem {
                    Label("Read Text", systemImage: "text.viewfinder")
                }

            FaceRecognitionView()
                .tabItem {
                    Label("Face Recognition", systemImage: "person.crop.rectangle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    RootTabView()
        .environmentObject(SettingsStore())
}