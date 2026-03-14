import Foundation

enum FaceModelContract {
    static let modelFilename = "arcface_fresh"
    static let modelExtension = "onnx"
    static let inputName = "input_1"
    static let outputName = "embedding"
    static let inputDimensionCount = 4
    static let inputShape = [1, 112, 112, 3]
    static let imageWidth = 112
    static let imageHeight = 112
    static let channels = 3
    static let normalizationOffset: Float = 127.5
    static let normalizationScale: Float = 128.0
    static let defaultEmbeddingSize = 512
}
