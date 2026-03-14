import Foundation

enum QuickCaptionLength: String, CaseIterable, Identifiable {
    case short
    case normal
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short:
            return "Short"
        case .normal:
            return "Normal"
        case .long:
            return "Long"
        }
    }
}

enum QuickContinuousCaptureInterval: Double, CaseIterable, Identifiable {
    case oneSecond = 1
    case twoSeconds = 2
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120

    static let defaultInterval: Self = .threeSeconds

    var id: Double { rawValue }

    var timeInterval: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .oneSecond:
            return "1 second"
        case .twoSeconds:
            return "2 seconds"
        case .threeSeconds:
            return "3 seconds"
        case .fiveSeconds:
            return "5 seconds"
        case .tenSeconds:
            return "10 seconds"
        case .thirtySeconds:
            return "30 seconds"
        case .oneMinute:
            return "1 minute"
        case .twoMinutes:
            return "2 minutes"
        }
    }
}

struct QuickQueryPreset: Identifiable, Equatable {
    let title: String
    let prompt: String
    let systemImageName: String

    var id: String { title }

    static let builtIn: [QuickQueryPreset] = [
        QuickQueryPreset(
            title: "Product",
            prompt: "Describe the main product in this image with 1 or 2 sentences, including its brand, name and primary function",
            systemImageName: "shippingbox.fill"
        ),
        QuickQueryPreset(
            title: "Dish",
            prompt: "Describe the layout of the food on the plate or tray. Use clock positions or spatial terms",
            systemImageName: "fork.knife.circle.fill"
        ),
        QuickQueryPreset(
            title: "Short Text",
            prompt: "Describe the alphanumeric text visible in the image",
            systemImageName: "text.magnifyingglass"
        )
    ]
}

enum QuickCustomQueryPreset {
    static let defaultTitle = "Custom"
    static let defaultPrompt = "Tell me how many men and women there and describe them; if not found, say No people found"
}

enum QuickTranslationSupport {
    static func shouldAttemptTranslation(
        for caption: String,
        isTranslationEnabled: Bool,
        targetLanguageIdentifier: String?
    ) -> Bool {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCaption.isEmpty else { return false }
        guard isTranslationEnabled else { return false }
        guard let targetLanguageIdentifier, !targetLanguageIdentifier.isEmpty else { return false }

        let targetCode = Locale(identifier: targetLanguageIdentifier).language.languageCode?.identifier.lowercased()
        let sourceCode = Locale(identifier: "en-US").language.languageCode?.identifier.lowercased()
        return targetCode != nil && targetCode != sourceCode
    }
}
