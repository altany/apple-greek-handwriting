import Foundation

/// Finds where ML Kit put its downloaded models inside this process's container.
/// Needed to plan how the keyboard gets the model (risk 2 in CLAUDE.md).
enum ModelStorageInspector {
    static func report() -> String {
        let fm = FileManager.default
        var lines: [String] = []
        let roots: [(String, FileManager.SearchPathDirectory)] = [
            ("Application Support", .applicationSupportDirectory),
            ("Caches", .cachesDirectory),
            ("Documents", .documentDirectory),
        ]
        for (name, dir) in roots {
            guard let root = fm.urls(for: dir, in: .userDomainMask).first else { continue }
            lines.append("\(name): \(root.path)")
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let size = directorySize(item)
                lines.append(String(format: "  %@  %.1f MB", item.lastPathComponent, Double(size) / 1_048_576))
                if item.lastPathComponent.lowercased().contains("mlkit") {
                    lines.append(contentsOf: tree(item, depth: 3, indent: "    "))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func tree(_ url: URL, depth: Int, indent: String) -> [String] {
        guard depth > 0, let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else { return [] }
        var out: [String] = []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let size = isDir ? directorySize(item) : ((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            out.append(String(format: "%@%@%@  %.1f MB", indent, item.lastPathComponent, isDir ? "/" : "", Double(size) / 1_048_576))
            if isDir { out.append(contentsOf: tree(item, depth: depth - 1, indent: indent + "  ")) }
        }
        return out
    }

    private static func directorySize(_ url: URL) -> Int {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let f as URL in e { total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }
}
