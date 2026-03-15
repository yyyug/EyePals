import Foundation

struct FaceSuggestion: Identifiable, Equatable {
    let id: UUID
    let sampleEmbeddings: [[Float]]
    let jpegData: Data?
    let createdAt: Date

    var embedding: [Float] {
        sampleEmbeddings.first ?? []
    }

    init(id: UUID = UUID(), sampleEmbeddings: [[Float]], jpegData: Data?, createdAt: Date = .now) {
        self.id = id
        self.sampleEmbeddings = sampleEmbeddings
        self.jpegData = jpegData
        self.createdAt = createdAt
    }

    init(id: UUID = UUID(), embedding: [Float], jpegData: Data?, createdAt: Date = .now) {
        self.init(id: id, sampleEmbeddings: [embedding], jpegData: jpegData, createdAt: createdAt)
    }
}
