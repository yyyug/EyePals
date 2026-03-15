import SwiftUI
#if canImport(Translation)
import Translation
#endif

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore

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

                Section("Features") {
                    NavigationLink("Details Description") {
                        DetailsDescriptionSettingsView()
                            .environmentObject(openAIStore)
                    }

                    NavigationLink("Quick Recognition") {
                        QuickRecognitionSettingsView()
                            .environmentObject(settingsStore)
                    }

                    NavigationLink("Face Recognition") {
                        FaceRecognitionSettingsView()
                            .environmentObject(settingsStore)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(OpenAISubscriptionStore())
}

private struct DetailsDescriptionSettingsView: View {
    @EnvironmentObject private var openAIStore: OpenAISubscriptionStore

    var body: some View {
        Form {
            if openAIStore.isSignedIn {
                Section {
                    Button("Sign Out", role: .destructive) {
                        openAIStore.signOut()
                    }
                }
            } else {
                Section {
                    Text("Not signed in.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Details Description")
    }
}

private struct QuickRecognitionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    #if canImport(Translation)
    @StateObject private var translationLanguageStore = TranslationLanguageStore()
    #endif

    private var selectedCaptionLength: Binding<QuickCaptionLength> {
        Binding(
            get: { QuickCaptionLength(rawValue: settingsStore.quickCaptionLength) ?? .short },
            set: { settingsStore.quickCaptionLength = $0.rawValue }
        )
    }

    private var selectedContinuousCaptureInterval: Binding<QuickContinuousCaptureInterval> {
        Binding(
            get: { QuickContinuousCaptureInterval(rawValue: settingsStore.quickContinuousCaptureInterval) ?? .defaultInterval },
            set: { settingsStore.quickContinuousCaptureInterval = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $settingsStore.quickMoondreamAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Take Photo") {
                Picker("Caption Length", selection: selectedCaptionLength) {
                    ForEach(QuickCaptionLength.allCases) { length in
                        Text(length.displayName).tag(length)
                    }
                }

                Text("This setting applies to Take Photo only. Continuous mode uses the short caption style.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Continuous Mode") {
                Picker("Capture Frequency", selection: selectedContinuousCaptureInterval) {
                    ForEach(QuickContinuousCaptureInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }

                Text("Choose how often Continuous mode takes a picture. Each completed result is announced when available.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Custom Button") {
                TextField("Button Name", text: $settingsStore.quickCustomQueryTitle)
                    .textInputAutocapitalization(.words)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $settingsStore.quickCustomQueryPrompt)
                        .frame(minHeight: 120)
                }

                Text("This button appears to the left of Product and uses the prompt you save here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            translationSection
        }
        .navigationTitle("Quick Recognition")
        #if canImport(Translation)
        .task {
            if #available(iOS 18.0, *) {
                await translationLanguageStore.loadLanguages()
                refreshSelectedLanguageIfNeeded()
            }
        }
        #endif
    }

    @ViewBuilder
    private var translationSection: some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            Section("Translation") {
                Toggle("Enable Translation", isOn: $settingsStore.quickCaptionTranslationEnabled)
                    .disabled(!translationLanguageStore.hasAvailableLanguages)

                if translationLanguageStore.isLoading {
                    LabeledContent("Target Language") {
                        Text("Loading available languages...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage = translationLanguageStore.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if translationLanguageStore.availableLanguages.isEmpty {
                    Text("No translation languages are currently available on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Target Language", selection: $settingsStore.quickCaptionTranslationTargetLanguage) {
                        Text("Choose a language").tag("")

                        ForEach(translationLanguageStore.availableLanguages) { language in
                            Text(language.displayName).tag(language.identifier)
                        }
                    }
                    .disabled(!settingsStore.quickCaptionTranslationEnabled)
                }

                Text("Translate Quick Recognition results into the language you choose below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Translation") {
                Text("Translation is unavailable on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        #else
        Section("Translation") {
            Text("Translation is unavailable on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        #endif
    }

    #if canImport(Translation)
    private func refreshSelectedLanguageIfNeeded() {
        guard !translationLanguageStore.isLoading else { return }

        if translationLanguageStore.availableLanguages.isEmpty {
            settingsStore.quickCaptionTranslationTargetLanguage = ""
            settingsStore.quickCaptionTranslationEnabled = false
            return
        }

        if settingsStore.quickCaptionTranslationTargetLanguage.isEmpty {
            return
        }

        let selectedLanguageStillAvailable = translationLanguageStore.availableLanguages.contains {
            $0.identifier == settingsStore.quickCaptionTranslationTargetLanguage
        }

        if !selectedLanguageStillAvailable {
            settingsStore.quickCaptionTranslationTargetLanguage = ""
        }
    }
    #endif
}

private struct FaceRecognitionSettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section("Recognition") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Match sensitivity")
                    Slider(value: $settingsStore.faceMatchThreshold, in: 0.84...0.98, step: 0.01)
                    Text(settingsStore.faceMatchThreshold.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Suggest unknown faces", isOn: $settingsStore.suggestUnknownFaces)
            }

            Section("Saved Faces") {
                NavigationLink("Manage Saved Faces") {
                    SavedFacesView()
                }
            }

            Section("Training Tips") {
                Text("Save a face in bright, even lighting.")
                Text("Capture the person from a comfortable conversation distance.")
                Text("If recognition is inconsistent, save a fresh sample for that person.")
            }
        }
        .navigationTitle("Face Recognition")
    }
}

private struct SavedFacesView: View {
    @StateObject private var viewModel = SavedFacesViewModel()
    @State private var renamingProfile: FaceProfile?
    @State private var draftName = ""

    var body: some View {
        List {
            if viewModel.profiles.isEmpty {
                Text("No faces have been saved yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.profiles) { profile in
                    HStack {
                        Text(profile.name)
                        Spacer()
                        Button("Rename") {
                            draftName = profile.name
                            renamingProfile = profile
                        }
                        .buttonStyle(.borderless)
                    }
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
        .alert("Rename Face", isPresented: Binding(get: { renamingProfile != nil }, set: { if !$0 { renamingProfile = nil } })) {
            TextField("Person's name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {
                renamingProfile = nil
                draftName = ""
            }
            Button("Save") {
                guard let renamingProfile else { return }
                viewModel.renameProfile(id: renamingProfile.id, newName: draftName)
                self.renamingProfile = nil
                draftName = ""
            }
        } message: {
            Text("Enter a new name for this saved face.")
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

    func renameProfile(id: UUID, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        var updatedProfiles = profiles
        guard let profileIndex = updatedProfiles.firstIndex(where: { $0.id == id }) else { return }

        updatedProfiles[profileIndex].name = trimmedName
        updatedProfiles[profileIndex].updatedAt = .now

        Task {
            do {
                try await faceStore.saveProfiles(updatedProfiles)
                profiles = updatedProfiles
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if canImport(Translation)
@MainActor
private final class TranslationLanguageStore: ObservableObject {
    @Published private(set) var availableLanguages: [TranslationLanguageOption] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var hasAvailableLanguages: Bool {
        !availableLanguages.isEmpty
    }

    func loadLanguages() async {
        guard availableLanguages.isEmpty, !isLoading else { return }

        isLoading = true
        errorMessage = nil

        if #available(iOS 18.0, *) {
            do {
                let supportedLanguages = try await LanguageAvailability().supportedLanguages
                availableLanguages = supportedLanguages
                    .map(TranslationLanguageOption.init)
                    .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            } catch {
                errorMessage = "Unable to load translation languages right now."
                availableLanguages = []
            }
        } else {
            errorMessage = "Translation is unavailable on this device."
            availableLanguages = []
        }

        isLoading = false
    }
}

private struct TranslationLanguageOption: Identifiable, Equatable {
    let identifier: String

    @available(iOS 18.0, *)
    init(language: Locale.Language) {
        if !language.maximalIdentifier.isEmpty {
            identifier = language.maximalIdentifier
        } else if !language.minimalIdentifier.isEmpty {
            identifier = language.minimalIdentifier
        } else {
            identifier = String(describing: language)
        }
    }

    var id: String { identifier }

    var displayName: String {
        if let localizedName = Locale.current.localizedString(forIdentifier: identifier), !localizedName.isEmpty {
            return localizedName
        }

        return identifier
    }
}
#endif
