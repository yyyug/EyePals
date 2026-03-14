import SwiftUI

struct ReadTextView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = ReadTextViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.cameraStateDescription)
                        .font(.headline)

                    Text(viewModel.recognizedText)
                        .font(.title3.weight(.semibold))
                        .accessibilityLabel("Recognized text")

                    Text("Language: \(viewModel.detectedLanguage)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.capturePhoto()
                    } label: {
                        Label(viewModel.isCapturingPhoto ? "Reading Photo..." : "Take Picture", systemImage: "camera")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCapturingPhoto)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .navigationTitle("Read Text")
            .sheet(item: $viewModel.capturedResult, onDismiss: {
                viewModel.dismissCapturedResult()
            }) { result in
                CapturedTextResultView(result: result)
            }
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
    ReadTextView()
        .environmentObject(SettingsStore())
}

private struct CapturedTextResultView: View {
    let result: ReadTextViewModel.CapturedTextResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(result.text)
                        .font(.title3)
                        .textSelection(.enabled)

                    Text("Language: \(result.language)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Captured Text")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
