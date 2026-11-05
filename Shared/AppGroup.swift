import Foundation

/// Access to the App Group container shared by the app and the keyboard.
/// Phase 0 uses it only to test what the keyboard can read/write without Full Access.
enum AppGroup {
    /// Comes from Info.plist (`AppGroupIdentifier`), which Xcode fills from Local.xcconfig.
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
            ?? "group.com.tany4.greekink"
    }

    /// nil means iOS did not grant this process the group (missing entitlement,
    /// or a keyboard without Full Access).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static var pingURL: URL? { containerURL?.appendingPathComponent("ping.txt") }

    /// Writes "<who> @ <time>" into the shared container.
    static func writePing(from who: String) -> String {
        guard let url = pingURL else { return "write: no container (group not granted)" }
        let text = "\(who) @ \(Self.timestamp())"
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return "write OK: \"\(text)\""
        } catch {
            return "write FAILED: \(error.localizedDescription)"
        }
    }

    /// Reads whatever was last written (by either process).
    static func readPing() -> String {
        guard let url = pingURL else { return "read: no container (group not granted)" }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            return "read OK: \"\(text)\""
        } catch {
            return "read FAILED: \(error.localizedDescription)"
        }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
