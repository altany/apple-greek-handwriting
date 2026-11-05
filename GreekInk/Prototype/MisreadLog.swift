import Foundation

struct MisreadEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let language: String
    let expected: String
    let candidates: [String]
    let strokes: Int
}

/// Small log of what the recogniser got wrong. Stored as JSON in Documents
/// (visible in the Files app, since the app has file sharing enabled).
@MainActor
final class MisreadLog: ObservableObject {
    @Published private(set) var entries: [MisreadEntry] = []

    private let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("misreads.json")
    }()

    init() { load() }

    func add(_ entry: MisreadEntry) {
        entries.insert(entry, at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    var asText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return entries.map { e in
            "\(f.string(from: e.date)) [\(e.language), \(e.strokes) strokes] wrote: \(e.expected) | got: \(e.candidates.joined(separator: " / "))"
        }.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MisreadEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
