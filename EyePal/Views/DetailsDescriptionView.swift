import SwiftUI
import WebKit

struct DetailsDescriptionView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore
    @StateObject private var viewModel = DetailsDescriptionViewModel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CameraPreviewView(session: viewModel.camera.session)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.statusText)
                        .font(.headline)

                    if !openAIStore.isSignedIn {
                        Text("Sign in with ChatGPT to use scene description.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button("Sign In with ChatGPT") {
                            openAIStore.beginSignIn()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        if !viewModel.descriptionText.isEmpty {
                            ScrollView {
                                Text(viewModel.descriptionText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                            .accessibilityLabel("Scene description")
                        }

                        HStack(spacing: 12) {
                            Button {
                                if viewModel.descriptionText.isEmpty {
                                    viewModel.capturePhoto()
                                } else {
                                    viewModel.retake()
                                }
                            } label: {
                                Label(
                                    viewModel.descriptionText.isEmpty ? (viewModel.isProcessing ? "Working..." : "Take Photo") : "Retake Photo",
                                    systemImage: viewModel.descriptionText.isEmpty ? "camera" : "arrow.clockwise"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(viewModel.isProcessing)
                        }

                        if !viewModel.descriptionText.isEmpty {
                            HStack(spacing: 8) {
                                TextField("Ask a follow-up question", text: $viewModel.followUpQuestion)
                                    .textFieldStyle(.roundedBorder)
                                    .submitLabel(.send)
                                    .onSubmit {
                                        viewModel.submitFollowUp()
                                    }

                                Button("Send") {
                                    viewModel.submitFollowUp()
                                }
                                .buttonStyle(.bordered)
                                .disabled(viewModel.isProcessing || viewModel.followUpQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding()
            }
            .navigationTitle("Details Description")
            .sheet(item: $openAIStore.authRequest, onDismiss: {
                openAIStore.cancelSignIn()
            }) { authRequest in
                OpenAILoginSheet(
                    url: authRequest.url,
                    callbackPrefix: "http://localhost:1455/auth/callback"
                ) { callbackURL in
                    openAIStore.handleAuthorizationCallback(callbackURL)
                }
            }
            .alert(
                "OpenAI Sign-In Error",
                isPresented: Binding(
                    get: { openAIStore.authErrorMessage != nil },
                    set: { if !$0 { openAIStore.authErrorMessage = nil } }
                )
            ) {
                Button("OK") {
                    openAIStore.authErrorMessage = nil
                }
            } message: {
                Text(openAIStore.authErrorMessage ?? "")
            }
            .alert(
                "Details Description Error",
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
            viewModel.bind(openAIStore: openAIStore)
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
        .onChange(of: openAIStore.isSignedIn) { isSignedIn in
            if !isSignedIn {
                viewModel.retake()
            }
        }
    }
}

private struct OpenAILoginSheet: View {
    let url: URL
    let callbackPrefix: String
    let onCallback: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OpenAILoginWebView(url: url, callbackPrefix: callbackPrefix) { callbackURL in
                onCallback(callbackURL)
                dismiss()
            }
            .navigationTitle("ChatGPT Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct OpenAILoginWebView: UIViewRepresentable {
    let url: URL
    let callbackPrefix: String
    let onCallback: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(callbackPrefix: callbackPrefix, onCallback: onCallback)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let callbackPrefix: String
        private let onCallback: (URL) -> Void

        init(callbackPrefix: String, onCallback: @escaping (URL) -> Void) {
            self.callbackPrefix = callbackPrefix
            self.onCallback = onCallback
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url,
               url.absoluteString.hasPrefix(callbackPrefix) {
                onCallback(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}

#Preview {
    DetailsDescriptionView()
        .environmentObject(OpenAISubscriptionStore())
}
