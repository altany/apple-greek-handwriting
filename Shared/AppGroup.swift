import Foundation

/// Access to the App Group container shared by the app and the keyboard.
/// The app writes; a keyboard without Full Access can only read (verified in Phase 0).
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

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
