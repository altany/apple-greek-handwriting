import Foundation

/// Keeps the App Group copy of the ML Kit model in step with what the app has downloaded,
/// so the keyboard (no network without Full Access) can use it. See `ModelSharing`.
@MainActor
final class KeyboardModelExporter: ObservableObject {
    @Published private(set) var manifest: ModelSharing.Manifest? = ModelSharing.sharedManifest()
    @Published private(set) var message = ""

    /// Copies again when the shared copy is missing or lists other languages than are downloaded now.
    func exportIfNeeded(service: InkRecognitionService) {
        let languages = Self.downloaded(service)
        guard !languages.isEmpty, manifest?.languages != languages else { return }
        export(service: service, trigger: "auto")
    }

    func export(service: InkRecognitionService, trigger: String = "manual") {
        let languages = Self.downloaded(service)
        do {
            let m = try ModelSharing.exportToAppGroup(languages: languages)
            manifest = m
            message = "Copied for the keyboard at \(AppGroup.timestamp())"
            DiagnosticsLog.shared.log("model export \(trigger): \(m.languages.joined(separator: "+")), \(m.bytes) bytes")
        } catch {
            message = "Copy failed: \(error.localizedDescription)"
            DiagnosticsLog.shared.log("model export \(trigger) FAILED: \(error)")
        }
    }

    var summary: String {
        guard let m = manifest else { return "Not shared yet" }
        let when = m.exportedAt.formatted(date: .abbreviated, time: .shortened)
        let mb = String(format: "%.1f MB", Double(m.bytes) / 1_048_576)
        return "\(m.languages.joined(separator: " + ")) · \(mb) · \(when)"
    }

    private static func downloaded(_ service: InkRecognitionService) -> [String] {
        InkLanguage.allCases.filter { service.isDownloaded($0) }.map(\.rawValue).sorted()
    }
}
