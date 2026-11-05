import Foundation

/// Appends one line per event to Documents/diagnostics.log of THIS process (app or keyboard),
/// so the file can be pulled off the iPad without copy-paste:
///   xcrun devicectl device copy from --device <udid> --domain-type appDataContainer \
///     --domain-identifier com.tany4.greekink[.keyboard] --source Documents/diagnostics.log --destination .
/// Keeps the file small by dropping the oldest half once it passes 256 KB.
@MainActor
final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private let url: URL
    private let maxBytes = 256 * 1024
    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        url = docs.appendingPathComponent("diagnostics.log")
    }

    func log(_ line: String) {
        let entry = Data("\(clock.string(from: Date())) \(line)\n".utf8)
        trimIfNeeded()
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: entry)
            try? handle.close()
        } else {
            try? entry.write(to: url)
        }
    }

    private func trimIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: url) else { return }
        try? data.suffix(maxBytes / 2).write(to: url)
    }
}
