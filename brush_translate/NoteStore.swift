import Foundation

struct NoteEntry: Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let source: String
    let translated: String
}

final class NoteStore {
    static let shared = NoteStore()

    private let fileURL: URL
    private var entries: [NoteEntry] = []
    private let queue = DispatchQueue(label: "note.store.queue")

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("brush_translate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("notes.json")
        self.entries = (try? Self.load(from: fileURL)) ?? []
    }

    func add(source: String, translated: String) {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranslated = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty || !trimmedTranslated.isEmpty else { return }

        let entry = NoteEntry(id: UUID(), createdAt: Date(), source: trimmedSource, translated: trimmedTranslated)
        queue.async {
            self.entries.append(entry)
            self.persist()
        }
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL)
        }
    }

    private static func load(from url: URL) throws -> [NoteEntry] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([NoteEntry].self, from: data)
    }
}
