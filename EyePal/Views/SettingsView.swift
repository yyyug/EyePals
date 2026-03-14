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

                    NavigationLink("Saved Faces") {
                        SavedFacesView()
                    }
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

private struct SavedFacesView: View {
    @StateObject private var viewModel = SavedFacesViewModel()

    var body: some View {
        List {
            if viewModel.profiles.isEmpty {
                Text("No faces have been saved yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.profiles) { profile in
                    Text(profile.name)
                }
                .onDelete(perform: viewModel.deleteFaces)
            }
        }
        .navigationTitle("Saved Faces")
        .task {
            viewModel.loadProfiles()
        }
        .alert("Saved Faces Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

@MainActor
private final class SavedFacesViewModel: ObservableObject {
    @Published var profiles: [FaceProfile] = []
    @Published var errorMessage: String?

    private let faceStore = FaceStore()

    func loadProfiles() {
        Task {
            do {
                profiles = try await faceStore.loadProfiles()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func deleteFaces(at offsets: IndexSet) {
        let deletedProfiles = offsets.compactMap { index in
            profiles.indices.contains(index) ? profiles[index] : nil
        }
        let remainingProfiles = profiles.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map(\.element)

        Task {
            do {
                for profile in deletedProfiles {
                    if let filename = profile.sampleImageFilename {
                        try await faceStore.deleteImage(named: filename)
                    }
                }
                try await faceStore.saveProfiles(remainingProfiles)
                profiles = remainingProfiles
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
