import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Speech") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Announcement cooldown")
                        Slider(value: $settingsStore.speechCooldown, in: 1...6, step: 0.5)
                        Text("\(settingsStore.speechCooldown.formatted(.number.precision(.fractionLength(1)))) seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Face Recognition") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Match sensitivity")
                        Slider(value: $settingsStore.faceMatchThreshold, in: 0.65...0.95, step: 0.01)
                        Text(settingsStore.faceMatchThreshold.formatted(.percent.precision(.fractionLength(0))))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Suggest unknown faces", isOn: $settingsStore.suggestUnknownFaces)
                }

                Section("Training Tips") {
                    Text("Save a face in bright, even lighting.")
                    Text("Capture the person from a comfortable conversation distance.")
                    Text("If recognition is inconsistent, save a fresh sample for that person.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
}