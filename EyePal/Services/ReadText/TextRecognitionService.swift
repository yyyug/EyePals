import AVFoundation
import MLKitLanguageID
import MLKitTextRecognition
import MLKitTextRecognitionChinese
import MLKitTextRecognitionCommon
import MLKitTextRecognitionDevanagari
import MLKitTextRecognitionJapanese
import MLKitTextRecognitionKorean
import MLKitVision
import UIKit

struct TextRecognitionObservation: Equatable {
    let text: String
    let languageCode: String?
}

final class TextRecognitionService {
    private enum ScriptRecognizer: CaseIterable {
        case latin
        case chinese
        case devanagari
        case japanese
        case korean

        var recognizer: TextRecognizer {
            switch self {
            case .latin:
                return TextRecognizer.textRecognizer()
            case .chinese:
                return TextRecognizer.textRecognizer(options: ChineseTextRecognizerOptions())
            case .devanagari:
                return TextRecognizer.textRecognizer(options: DevanagariTextRecognizerOptions())
            case .japanese:
                return TextRecognizer.textRecognizer(options: JapaneseTextRecognizerOptions())
            case .korean:
                return TextRecognizer.textRecognizer(options: KoreanTextRecognizerOptions())
            }
        }
    }

    private let processingQueue = DispatchQueue(label: "com.eyepals.text.recognition")
    private let languageIdentifier = LanguageIdentification.languageIdentification()
    private var isProcessingFrame = false
    private var lastSuccessfulScript: ScriptRecognizer = .latin

    func process(
        sampleBuffer: CMSampleBuffer,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        processingQueue.async {
            guard !self.isProcessingFrame else { return }
            self.isProcessingFrame = true

            let image = VisionImage(buffer: sampleBuffer)
            image.orientation = .right

            let scripts = [self.lastSuccessfulScript] + ScriptRecognizer.allCases.filter { $0 != self.lastSuccessfulScript }
            self.processScripts(scripts, image: image) { observation in
                Task { @MainActor in
                    completion(observation)
                }
                self.processingQueue.async {
                    self.isProcessingFrame = false
                }
            }
        }
    }

    func process(
        image: UIImage,
        completion: @escaping @MainActor (TextRecognitionObservation?) -> Void
    ) {
        processingQueue.async {
            let visionImage = VisionImage(image: image)
            visionImage.orientation = image.imageOrientation.mlKitOrientation

            let scripts = [self.lastSuccessfulScript] + ScriptRecognizer.allCases.filter { $0 != self.lastSuccessfulScript }
            self.processScripts(scripts, image: visionImage) { observation in
                Task { @MainActor in
                    completion(observation)
                }
            }
        }
    }

    private func processScripts(
        _ scripts: [ScriptRecognizer],
        image: VisionImage,
        completion: @escaping (TextRecognitionObservation?) -> Void
    ) {
        guard let script = scripts.first else {
            completion(nil)
            return
        }

        script.recognizer.process(image) { [weak self] result, error in
            guard let self else {
                completion(nil)
                return
            }

            if error != nil {
                self.processScripts(Array(scripts.dropFirst()), image: image, completion: completion)
                return
            }

            let text = result?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                self.processScripts(Array(scripts.dropFirst()), image: image, completion: completion)
                return
            }

            self.lastSuccessfulScript = script
            self.languageIdentifier.identifyLanguage(for: text) { code, _ in
                completion(TextRecognitionObservation(text: text, languageCode: code))
            }
        }
    }
}

private extension UIImage.Orientation {
    var mlKitOrientation: UIImageOrientation {
        switch self {
        case .up:
            return .topLeft
        case .down:
            return .bottomRight
        case .left:
            return .leftBottom
        case .right:
            return .rightTop
        case .upMirrored:
            return .topRight
        case .downMirrored:
            return .bottomLeft
        case .leftMirrored:
            return .leftTop
        case .rightMirrored:
            return .rightBottom
        @unknown default:
            return .topLeft
        }
    }
}
