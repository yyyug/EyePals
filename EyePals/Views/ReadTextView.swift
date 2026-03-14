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
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .navigationTitle("Read Text")
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