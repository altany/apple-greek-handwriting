import Foundation

/// Gets the ML Kit model from the host app into the keyboard without network access.
///
/// ML Kit keeps its models in `Library/Application Support/<mlkitFolderName>` of the process
/// that downloaded them, and offers no API to point it elsewhere. A keyboard without Full
/// Access has no network and can only READ the App Group container. So:
///   1. the host app copies its ML Kit folder into the App Group (`exportToAppGroup`),
///   2. the keyboard copies that into its own container, where ML Kit looks
///      (`importIntoKeyboard`), BEFORE it touches any ML Kit API.
/// A plain copy (not a symlink) keeps the keyboard's copy writable, which ML Kit's download
/// manager (MDD) wants for its lock file. On APFS the copy is a clone, so it costs no time and
/// little disk.
///
/// MDD names its metadata files `<bundle id>.com.google.mlkit.mdd…`, and the keyboard has a
/// different bundle id than the app, so the import also adds copies under the keyboard's id.
enum ModelSharing {
    static let mlkitFolderName = "com.google.mlkit.vision.digitalinkrecognition"

    struct Manifest: Codable, Equatable {
        var exportedAt: Date
        var sourceBundleID: String
        var languages: [String]
        var bytes: Int
    }

    // MARK: Locations

    /// Where ML Kit keeps models for THIS process.
    static var localFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(mlkitFolderName, isDirectory: true)
    }

    private static var sharedRoot: URL? {
        AppGroup.containerURL?.appendingPathComponent("SharedModel", isDirectory: true)
    }
    private static var sharedFolder: URL? { sharedRoot?.appendingPathComponent(mlkitFolderName, isDirectory: true) }
    private static var manifestURL: URL? { sharedRoot?.appendingPathComponent("manifest.json") }

    /// What the keyboard last imported (lives next to ML Kit's folder in the keyboard's container).
    private static var importStampURL: URL {
        localFolder.deletingLastPathComponent().appendingPathComponent("greekink-imported-model.json")
    }

    /// Download-session state; copying it into another process makes no sense.
    private static let skippedNames: Set<String> = ["scratch"]

    // MARK: Host app

    static func sharedManifest() -> Manifest? {
        guard let url = manifestURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Manifest.self, from: data)
    }

    /// Replaces the App Group copy with the app's current ML Kit folder.
    @discardableResult
    static func exportToAppGroup(languages: [String]) throws -> Manifest {
        let fm = FileManager.default
        guard let root = sharedRoot, let folder = sharedFolder, let manifestURL else {
            throw SharingError.noAppGroup
        }
        guard fm.fileExists(atPath: localFolder.path) else { throw SharingError.nothingToExport }
        if fm.fileExists(atPath: root.path) { try fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try copyTree(from: localFolder, to: folder)
        let manifest = Manifest(exportedAt: Date(), sourceBundleID: Bundle.main.bundleIdentifier ?? "?",
                                languages: languages.sorted(), bytes: directorySize(folder))
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        return manifest
    }

    // MARK: Keyboard

    /// Copies the shared model into this process's ML Kit folder if it is missing or older than
    /// the App Group copy. Returns a one-line summary for the diagnostics log.
    static func importIntoKeyboard() -> String {
        let fm = FileManager.default
        guard let folder = sharedFolder else { return "import: App Group not granted" }
        guard let manifest = sharedManifest(), fm.fileExists(atPath: folder.path) else {
            return "import: no shared model yet (open GreekInk once with the model downloaded)"
        }
        if let data = try? Data(contentsOf: importStampURL),
           let imported = try? decoder.decode(Manifest.self, from: data),
           imported == manifest, fm.fileExists(atPath: localFolder.path) {
            return "import: up to date (\(manifest.languages.joined(separator: "+")), exported \(manifest.exportedAt))"
        }
        do {
            if fm.fileExists(atPath: localFolder.path) { try fm.removeItem(at: localFolder) }
            try fm.createDirectory(at: localFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try copyTree(from: folder, to: localFolder)
            let renamed = try addMetadataCopies(from: manifest.sourceBundleID, to: Bundle.main.bundleIdentifier ?? "")
            try encoder.encode(manifest).write(to: importStampURL, options: .atomic)
            let mb = Double(directorySize(localFolder)) / 1_048_576
            return String(format: "import: copied %.1f MB (%@), %d metadata files renamed",
                          mb, manifest.languages.joined(separator: "+"), renamed)
        } catch {
            return "import FAILED: \(error.localizedDescription)"
        }
    }

    /// For each `<from>.…` metadata file, writes a `<to>.…` copy next to it (keeps the original).
    private static func addMetadataCopies(from source: String, to target: String) throws -> Int {
        guard !source.isEmpty, !target.isEmpty, source != target else { return 0 }
        let fm = FileManager.default
        let dir = localFolder.appendingPathComponent("Download/FileGroupMetadata", isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return 0 }
        var count = 0
        for name in names where name.hasPrefix(source + ".") {
            let renamed = target + name.dropFirst(source.count)
            let dest = dir.appendingPathComponent(renamed)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: dir.appendingPathComponent(name), to: dest)
            count += 1
        }
        return count
    }

    // MARK: Helpers

    enum SharingError: LocalizedError {
        case noAppGroup, nothingToExport
        var errorDescription: String? {
            switch self {
            case .noAppGroup: return "App Group container not available"
            case .nothingToExport: return "No ML Kit model folder yet (download the model first)"
            }
        }
    }

    private static func copyTree(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: source.path) where !skippedNames.contains(name) {
            let from = source.appendingPathComponent(name)
            let to = dest.appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: from.path, isDirectory: &isDir)
            if isDir.boolValue { try copyTree(from: from, to: to) } else { try fm.copyItem(at: from, to: to) }
        }
    }

    static func directorySize(_ url: URL) -> Int {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let f as URL in e { total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }

    /// Relative paths and sizes under ML Kit's folder, for the diagnostics log.
    static func localTree() -> String {
        let root = localFolder
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) else {
            return "(no ML Kit folder)"
        }
        var lines: [String] = []
        for case let f as URL in e {
            let values = try? f.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true { continue }
            let rel = f.path.replacingOccurrences(of: root.path + "/", with: "")
            lines.append("  \(rel) \(values?.fileSize ?? 0)")
        }
        return lines.isEmpty ? "(empty)" : lines.sorted().joined(separator: "\n")
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
