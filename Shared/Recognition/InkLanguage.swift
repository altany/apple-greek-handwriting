import Foundation

/// Languages we recognise. Raw value is the ML Kit language tag.
enum InkLanguage: String, CaseIterable, Identifiable {
    case greek = "el"
    case english = "en"

    var id: String { rawValue }
    var label: String { self == .greek ? "Ελληνικά" : "English" }

    static let defaultsKey = "greekink.language"
    static var saved: InkLanguage {
        InkLanguage(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .greek
    }
}
