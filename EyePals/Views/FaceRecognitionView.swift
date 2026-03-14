import SwiftUI

struct FaceRecognitionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = FaceRecognitionViewModel()
    @State private var suggestedName = ""

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.statusText)
                        .font(.headline)

                    if let recognizedName = viewModel.recognizedName {
                        Text(recognizedName)
                            .font(.largeTitle.weight(.bold))
                    }

                    if !viewModel.profiles.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(viewModel.profiles) { profile in
                                    HStack {
                                        Text(profile.name)
                                        Button(role: .destructive) {
                                            viewModel.deleteProfile(id: profile.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .accessibilityLabel("Delete \(profile.name)")
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.thinMaterial, in: Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .navigationTitle("Face Recognition")
            .sheet(item: $viewModel.pendingSuggestion) { _ in
                NavigationStack {
                    Form {
                        Section("New Face") {
                            Text("EyePals found a stable unknown face. Save it only if you know this person.")
                            TextField("Person's name", text: $suggestedName)
                                .textInputAutocapitalization(.words)
                        }

                        Section("Why this matters") {
                            Text("Names and embeddings stay on this device. The app does not upload face data.")
                        }
                    }
                    .navigationTitle("Add Person")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Not Now") {
                                suggestedName = ""
                                viewModel.dismissSuggestion()
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                viewModel.saveSuggestion(named: suggestedName)
                                suggestedName = ""
                            }
                            .disabled(suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .alert("Face Recognition Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if (!$0) { viewModel.errorMessage = nil } }), actions: {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            }, message: {
                Text(viewModel.errorMessage ?? "")
            })
        }
        .onAppear {
            viewModel.bind(settings: settingsStore)
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

#Preview {
    FaceRecognitionView()
        .environmentObject(SettingsStore())
}
