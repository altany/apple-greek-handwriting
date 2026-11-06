import Foundation
import MLKit

struct RecognitionCandidate: Identifiable, Equatable {
    let id = UUID()
    let text: String
    /// ML Kit's score; nil for some models. Candidates are already ordered best first.
    let score: Double?
}

enum ModelState: Equatable {
    case notDownloaded, downloading, downloaded
    case failed(String)

    var label: String {
        switch self {
        case .notDownloaded: return "not downloaded"
        case .downloading: return "downloading…"
        case .downloaded: return "ready"
        case .failed(let why): return "failed: \(why)"
        }
    }
}

enum RecognitionError: LocalizedError {
    case unknownLanguage(String)
    case modelNotDownloaded(String)

    var errorDescription: String? {
        switch self {
        case .unknownLanguage(let tag): return "ML Kit has no model for language tag \(tag)"
        case .modelNotDownloaded(let tag): return "Model \(tag) is not downloaded"
        }
    }
}

/// ML Kit model tags that are not text languages.
enum InkModelTag {
    /// Gesture classifier for Greek (tag from the ML Kit base-models table). What it returns
    /// (scribble, strike-through…) is not documented: Phase 3 logs its output to find out.
    static let greekGestures = "el-x-gesture"
}

/// Thin wrapper over ML Kit Digital Ink: model download state + recognition.
/// Shared by the app and the keyboard. Everything is keyed by ML Kit model tag internally
/// ("el", "en", "el-x-gesture"); text languages also have `InkLanguage` conveniences.
@MainActor
final class InkRecognitionService: ObservableObject {

    /// All tags this service manages: the text languages, then the gesture classifier.
    static let allTags = InkLanguage.allCases.map(\.rawValue) + [InkModelTag.greekGestures]

    @Published private(set) var states: [String: ModelState] = [:]

    var modelStates: [InkLanguage: ModelState] {
        Dictionary(uniqueKeysWithValues: InkLanguage.allCases.map { ($0, states[$0.rawValue] ?? .notDownloaded) })
    }
    var gestureState: ModelState { states[InkModelTag.greekGestures] ?? .notDownloaded }

    private let modelManager = ModelManager.modelManager()
    /// Cached per tag, together with the maxResults it was built with.
    private var recognizers: [String: (recognizer: DigitalInkRecognizer, maxResults: Int)] = [:]
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .mlkitModelDownloadDidSucceed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshModelStates() }
        })
        observers.append(center.addObserver(forName: .mlkitModelDownloadDidFail, object: nil, queue: .main) { [weak self] note in
            let error = note.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? Error
            let model = note.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue] as? DigitalInkRecognitionModel
            Task { @MainActor in self?.downloadFailed(model: model, error: error) }
        })
        refreshModelStates()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: Models

    func model(forTag tag: String) throws -> DigitalInkRecognitionModel {
        guard let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: tag) else {
            throw RecognitionError.unknownLanguage(tag)
        }
        return DigitalInkRecognitionModel(modelIdentifier: identifier)
    }

    func isDownloaded(tag: String) -> Bool {
        guard let model = try? model(forTag: tag) else { return false }
        return modelManager.isModelDownloaded(model)
    }

    func isDownloaded(_ language: InkLanguage) -> Bool { isDownloaded(tag: language.rawValue) }

    /// Tags whose models are on disk, sorted (what the keyboard copy should contain).
    func downloadedTags() -> [String] { Self.allTags.filter { isDownloaded(tag: $0) }.sorted() }

    func refreshModelStates() {
        for tag in Self.allTags {
            if states[tag] == .downloading, !isDownloaded(tag: tag) { continue }
            states[tag] = isDownloaded(tag: tag) ? .downloaded : .notDownloaded
        }
    }

    func download(_ language: InkLanguage) { download(tag: language.rawValue) }

    func download(tag: String) {
        guard let model = try? model(forTag: tag) else {
            states[tag] = .failed("unknown model tag")
            return
        }
        if modelManager.isModelDownloaded(model) {
            states[tag] = .downloaded
            return
        }
        states[tag] = .downloading
        let conditions = ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: true)
        _ = modelManager.download(model, conditions: conditions)
    }

    func delete(_ language: InkLanguage) { delete(tag: language.rawValue) }

    func delete(tag: String) {
        guard let model = try? model(forTag: tag) else { return }
        recognizers[tag] = nil
        modelManager.deleteDownloadedModel(model) { [weak self] _ in
            Task { @MainActor in self?.refreshModelStates() }
        }
    }

    private func downloadFailed(model: DigitalInkRecognitionModel?, error: Error?) {
        let why = error?.localizedDescription ?? "unknown error"
        for tag in Self.allTags where states[tag] == .downloading {
            if let model, let ours = try? self.model(forTag: tag), ours != model { continue }
            states[tag] = .failed(why)
        }
    }

    // MARK: Recognition

    /// Recognises the strokes. `writingArea` is the canvas size in the same units as the points.
    /// `preContext` is the text before the ink (ML Kit uses the last 20 characters). Returns up to
    /// `maxResults` candidates, best first. `requireDownloaded: false` skips the
    /// `isModelDownloaded` check (diagnostics: does ML Kit load the files anyway?).
    func recognize(_ strokes: [InkStroke],
                   language: InkLanguage,
                   preContext: String? = nil,
                   writingArea: CGSize? = nil,
                   maxResults: Int = 5,
                   requireDownloaded: Bool = true) async throws -> [RecognitionCandidate] {
        try await run(strokes, tag: language.rawValue, preContext: preContext, writingArea: writingArea,
                      maxResults: maxResults, requireDownloaded: requireDownloaded)
    }

    /// Runs the gesture classifier on the strokes. Candidates are gesture names, best first.
    func classifyGesture(_ strokes: [InkStroke], writingArea: CGSize? = nil, maxResults: Int = 3) async throws -> [RecognitionCandidate] {
        try await run(strokes, tag: InkModelTag.greekGestures, preContext: nil, writingArea: writingArea,
                      maxResults: maxResults, requireDownloaded: true)
    }

    private func run(_ strokes: [InkStroke], tag: String, preContext: String?, writingArea: CGSize?,
                     maxResults: Int, requireDownloaded: Bool) async throws -> [RecognitionCandidate] {
        let recognizer = try recognizer(forTag: tag, maxResults: maxResults, requireDownloaded: requireDownloaded)
        let ink = Ink(strokes: strokes.map { stroke in
            Stroke(points: stroke.points.map { p in
                StrokePoint(x: Float(p.x), y: Float(p.y), t: Int(p.t * 1000))
            })
        })
        let area = writingArea.map { WritingArea(width: Float($0.width), height: Float($0.height)) }
        // ML Kit 8.0.0 crashes (strlen on NULL inside recognitionForInk:context:error:) when
        // preContext is nil, even though the header marks it nullable. Always pass a string.
        let context = DigitalInkRecognitionContext(preContext: preContext ?? "", writingArea: area)

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognize(ink: ink, context: context) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let candidates = (result?.candidates ?? []).map {
                    RecognitionCandidate(text: $0.text, score: $0.score?.doubleValue)
                }
                continuation.resume(returning: candidates)
            }
        }
    }

    /// Drops cached recognizers (frees memory; useful in the keyboard).
    func releaseRecognizers() {
        recognizers.removeAll()
    }

    private func recognizer(forTag tag: String, maxResults: Int, requireDownloaded: Bool) throws -> DigitalInkRecognizer {
        // maxResults is fixed when the recognizer is built: rebuild if a caller asks for another count.
        if let cached = recognizers[tag], cached.maxResults == maxResults { return cached.recognizer }
        let model = try model(forTag: tag)
        guard !requireDownloaded || modelManager.isModelDownloaded(model) else {
            throw RecognitionError.modelNotDownloaded(tag)
        }
        let options = DigitalInkRecognizerOptions(model: model)
        options.maxResultCount = Int32(maxResults)
        let recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)
        recognizers[tag] = (recognizer, maxResults)
        return recognizer
    }
}
