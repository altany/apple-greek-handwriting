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
    case modelNotDownloaded(InkLanguage)

    var errorDescription: String? {
        switch self {
        case .unknownLanguage(let tag): return "ML Kit has no model for language tag \(tag)"
        case .modelNotDownloaded(let l): return "Model for \(l.label) is not downloaded"
        }
    }
}

/// Thin wrapper over ML Kit Digital Ink: model download state + recognition.
/// Shared by the app and (from Phase 2) the keyboard.
@MainActor
final class InkRecognitionService: ObservableObject {

    @Published private(set) var modelStates: [InkLanguage: ModelState] = [:]

    private let modelManager = ModelManager.modelManager()
    private var recognizers: [InkLanguage: DigitalInkRecognizer] = [:]
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

    func model(for language: InkLanguage) throws -> DigitalInkRecognitionModel {
        guard let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: language.rawValue) else {
            throw RecognitionError.unknownLanguage(language.rawValue)
        }
        return DigitalInkRecognitionModel(modelIdentifier: identifier)
    }

    func isDownloaded(_ language: InkLanguage) -> Bool {
        guard let model = try? model(for: language) else { return false }
        return modelManager.isModelDownloaded(model)
    }

    func refreshModelStates() {
        for language in InkLanguage.allCases {
            if modelStates[language] == .downloading, !isDownloaded(language) { continue }
            modelStates[language] = isDownloaded(language) ? .downloaded : .notDownloaded
        }
    }

    func download(_ language: InkLanguage) {
        guard let model = try? model(for: language) else {
            modelStates[language] = .failed("unknown language tag")
            return
        }
        if modelManager.isModelDownloaded(model) {
            modelStates[language] = .downloaded
            return
        }
        modelStates[language] = .downloading
        let conditions = ModelDownloadConditions(allowsCellularAccess: true, allowsBackgroundDownloading: true)
        _ = modelManager.download(model, conditions: conditions)
    }

    func delete(_ language: InkLanguage) {
        guard let model = try? model(for: language) else { return }
        recognizers[language] = nil
        modelManager.deleteDownloadedModel(model) { [weak self] _ in
            Task { @MainActor in self?.refreshModelStates() }
        }
    }

    private func downloadFailed(model: DigitalInkRecognitionModel?, error: Error?) {
        let why = error?.localizedDescription ?? "unknown error"
        for language in InkLanguage.allCases where modelStates[language] == .downloading {
            if let model, let ours = try? self.model(for: language), ours != model { continue }
            modelStates[language] = .failed(why)
        }
    }

    // MARK: Recognition

    /// Recognises the strokes. `writingArea` is the canvas size in the same units as the points.
    /// `preContext` is text before the cursor (Phase 3). Returns up to `maxResults` candidates, best first.
    func recognize(_ strokes: [InkStroke],
                   language: InkLanguage,
                   preContext: String? = nil,
                   writingArea: CGSize? = nil,
                   maxResults: Int = 5) async throws -> [RecognitionCandidate] {
        let recognizer = try recognizer(for: language, maxResults: maxResults)
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

    private func recognizer(for language: InkLanguage, maxResults: Int) throws -> DigitalInkRecognizer {
        if let cached = recognizers[language] { return cached }
        let model = try model(for: language)
        guard modelManager.isModelDownloaded(model) else { throw RecognitionError.modelNotDownloaded(language) }
        let options = DigitalInkRecognizerOptions(model: model)
        options.maxResultCount = Int32(maxResults)
        let recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: options)
        recognizers[language] = recognizer
        return recognizer
    }
}
