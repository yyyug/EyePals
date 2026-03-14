import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct QuickRecognitionView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @StateObject private var viewModel = QuickRecognitionViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.statusText)
                        .font(.headline)

                    if settingsStore.quickMoondreamAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add your Moondream API key in Settings > Quick Recognition.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !viewModel.responseText.isEmpty {
                        ScrollView {
                            Text(viewModel.responseText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                        .accessibilityLabel("Quick recognition result")
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button {
                                viewModel.takePhoto()
                            } label: {
                                Label(viewModel.isProcessing ? "Working..." : "Take Photo", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)

                            Button {
                                if viewModel.isContinuousCapture {
                                    viewModel.stopContinuousMode()
                                } else {
                                    viewModel.startContinuousMode()
                                }
                            } label: {
                                Label(
                                    viewModel.isContinuousCapture ? "Stop" : "Continuous",
                                    systemImage: viewModel.isContinuousCapture ? "stop.circle" : "play.circle"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isProcessing && !viewModel.isContinuousCapture)
                        }

                        HStack(spacing: 12) {
                            quickPresetButton(
                                title: customButtonTitle,
                                systemImage: "slider.horizontal.3"
                            ) {
                                viewModel.takeCustomPresetPhoto()
                            }

                            ForEach(QuickQueryPreset.builtIn) { preset in
                                quickPresetButton(
                                    title: preset.title,
                                    systemImage: preset.systemImageName
                                ) {
                                    viewModel.takePresetPhoto(preset)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()

                translationView
            }
            .navigationTitle("Quick Recognition")
            .alert(
                "Quick Recognition Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )
            ) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
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

    private var customButtonTitle: String {
        let trimmed = settingsStore.quickCustomQueryTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? QuickCustomQueryPreset.defaultTitle : trimmed
    }

    @ViewBuilder
    private func quickPresetButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.isProcessing || viewModel.isContinuousCapture)
    }

    @ViewBuilder
    private var translationView: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *), let request = viewModel.translationRequest {
            let configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en-US"),
                target: Locale.Language(identifier: request.targetLanguageIdentifier)
            )
            Color.clear
                .frame(width: 0, height: 0)
                .translationTask(configuration) { session in
                    do {
                        let response = try await session.translate(request.sourceText)
                        await MainActor.run {
                            guard viewModel.translationRequest?.id == request.id else { return }
                            viewModel.applyTranslatedResponse(
                                response.targetText,
                                fallbackText: request.sourceText
                            )
                        }
                    } catch {
                        await MainActor.run {
                            guard viewModel.translationRequest?.id == request.id else { return }
                            viewModel.applyTranslatedResponse(
                                request.sourceText,
                                fallbackText: request.sourceText
                            )
                        }
                    }
                }
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }
}

#Preview {
    QuickRecognitionView()
        .environmentObject(SettingsStore())
}
