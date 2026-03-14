import Foundation

struct FaceSuggestion: Identifiable, Equatable {
    let id: UUID
    let embedding: [Float]
    let jpegData: Data?
    let createdAt: Date

    init(id: UUID = UUID(), embedding: [Float], jpegData: Data?, createdAt: Date = .now) {
        self.id = id
        self.embedding = embedding
        self.jpegData = jpegData
        self.createdAt = createdAt
    }
}