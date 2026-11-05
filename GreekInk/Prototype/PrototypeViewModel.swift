import SwiftUI
import UIKit

@MainActor
final class PrototypeViewModel: ObservableObject {

    static let autoRecogniseDelay: Duration = .milliseconds(600)

    let canvas = InkCanvasView()
    let service: InkRecognitionService
    let log: MisreadLog

    @Published var language: InkLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: InkLanguage.defaultsKey)
            candidates = []
            selected = nil
            ensureModel()
            if strokeCount > 0 { recognizeNow() }
        }
    }
    @Published private(set) var candidates: [RecognitionCandidate] = []
    @Published var selected: RecognitionCandidate?
    @Published private(set) var status = "Write something"
    @Published private(set) var isRecognizing = false
    @Published private(set) var strokeCount = 0

    private var autoTask: Task<Void, Never>?

    init(service: InkRecognitionService, log: MisreadLog) {
        self.service = service
        self.log = log
        self.language = InkLanguage.saved
        canvas.onStrokeBegan = { [weak self] in self?.autoTask?.cancel() }
        canvas.onStrokeEnded = { [weak self] in self?.strokeEnded() }
    }

    func onAppear() {
        ensureModel()
    }

    var modelState: ModelState { service.modelStates[language] ?? .notDownloaded }

    func ensureModel() {
        if case .notDownloaded = modelState { service.download(language) }
    }

    private func strokeEnded() {
        strokeCount = canvas.strokes.count
        autoTask?.cancel()
        autoTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoRecogniseDelay)
            guard !Task.isCancelled else { return }
            await self?.recognize(trigger: "auto")
        }
    }

    func recognizeNow() {
        autoTask?.cancel()
        Task { await recognize(trigger: "manual") }
    }

    private func recognize(trigger: String) async {
        let strokes = canvas.strokes
        guard !strokes.isEmpty else { status = "Nothing to recognise"; return }
        guard modelState == .downloaded else { status = "Model for \(language.label) is \(modelState.label)"; return }
        isRecognizing = true
        let started = Date()
        do {
            let result = try await service.recognize(strokes, language: language,
                                                     writingArea: canvas.bounds.size, maxResults: 5)
            candidates = result
            selected = result.first
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let points = strokes.reduce(0) { $0 + $1.points.count }
            status = "\(trigger): \(result.count) candidates in \(ms) ms · \(strokes.count) strokes, \(points) points"
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
        isRecognizing = false
    }

    func clear() {
        autoTask?.cancel()
        canvas.clear()
        candidates = []
        selected = nil
        strokeCount = 0
        status = "Cleared"
    }

    func undoStroke() {
        canvas.undoLastStroke()
        strokeCount = canvas.strokes.count
        if strokeCount == 0 { clear() } else { strokeEnded() }
    }

    func copySelected() {
        guard let selected else { return }
        UIPasteboard.general.string = selected.text
        status = "Copied “\(selected.text)”"
    }

    func logMisread(expected: String) {
        log.add(MisreadEntry(date: Date(), language: language.rawValue, expected: expected,
                             candidates: candidates.map(\.text), strokes: strokeCount))
        status = "Logged misread (\(log.entries.count) total)"
    }
}
