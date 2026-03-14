import Foundation

struct FaceProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var embedding: [Float]
    var sampleImageFilename: String?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        embedding: [Float],
        sampleImageFilename: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.embedding = embedding
        self.sampleImageFilename = sampleImageFilename
    }
}