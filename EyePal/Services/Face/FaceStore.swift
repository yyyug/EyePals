import Foundation

actor FaceStore {
    private let fileManager = FileManager.default
    private let metadataURL: URL
    private let imagesDirectoryURL: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDirectory = appSupport.appendingPathComponent("EyePal", isDirectory: true)
        metadataURL = baseDirectory.appendingPathComponent("faces.json")
        imagesDirectoryURL = baseDirectory.appendingPathComponent("FaceImages", isDirectory: true)
    }

    func loadProfiles() throws -> [FaceProfile] {
        try ensureDirectories()

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return []
        }

        let data = try Data(contentsOf: metadataURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FaceProfile].self, from: data)
    }

    func saveProfiles(_ profiles: [FaceProfile]) throws {
        try ensureDirectories()
        let data = try JSONEncoder.prettyPrinted.encode(profiles)
        try data.write(to: metadataURL, options: .atomic)
    }

    func saveImage(_ data: Data, for faceID: UUID) throws -> String {
        try ensureDirectories()
        let filename = "\(faceID.uuidString).jpg"
        let url = imagesDirectoryURL.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return filename
    }

    func imageURL(for filename: String) -> URL {
        imagesDirectoryURL.appendingPathComponent(filename)
    }

    func deleteImage(named filename: String) throws {
        let url = imageURL(for: filename)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func ensureDirectories() throws {
        let baseDirectory = metadataURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        if !fileManager.fileExists(atPath: imagesDirectoryURL.path) {
            try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
