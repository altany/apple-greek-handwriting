import UIKit

/// The GreekInk keyboard: a writing strip, a candidate bar and a few keys.
///
/// Flow: write a word (or several) → pause → the ink is recognised, the top candidate is
/// inserted (with an automatic space before it) and the recognised strokes are cleared.
/// The candidate bar then shows the alternatives; tapping one swaps it in for the inserted word.
///
/// The model comes from the host app via the App Group (`ModelSharing`), because without
/// Full Access the keyboard has no network. The import must run before any ML Kit call.
final class KeyboardViewController: UIInputViewController {

    /// Pause after the last stroke before the ink is recognised and committed.
    /// Long enough to add a tonos or dialytika after the letters.
    static let commitDelay: Duration = .milliseconds(800)
    static let keyboardHeight: CGFloat = 300
    static let candidateCount = 5

    private let canvas = InkCanvasView()
    private let candidateStack = UIStackView()
    private var candidateButtons: [UIButton] = []
    private let statusLabel = UILabel()
    private var globeKey: UIButton!
    private var languageKey: UIButton!
    private var heightConstraint: NSLayoutConstraint?

    private var service: InkRecognitionService?
    /// Set when `isModelDownloaded` says no but a recognition still worked (diagnostics).
    private var skipDownloadCheck = false
    private var language: InkLanguage = InkLanguage.saved
    private var pauseTask: Task<Void, Never>?
    private var recognition: Task<Void, Never>?
    private var deleteRepeat: Timer?
    private let log = DiagnosticsLog.shared

    /// The word inserted last, so a tapped alternative can replace it.
    private struct Commit { var text: String; var alternatives: [String] }
    private var lastCommit: Commit?

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        log.log("keyboard loaded, full access \(hasFullAccess), \(MemoryFootprint.summary())")
        setStatus("loading model…")
        // File copy off the main thread; ML Kit is created only after it finishes.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ModelSharing.importIntoKeyboard()
            DispatchQueue.main.async { self?.modelImported(result) }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if heightConstraint == nil {
            // A keyboard sets its own height with a constraint on its root view.
            let c = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
        applyAppearance()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Don't insert into a text field the user just left.
        pauseTask?.cancel()
        canvas.clear()
        clearCandidates()
    }

    override func viewWillLayoutSubviews() {
        // The globe key is required only when the system says so.
        globeKey.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        applyAppearance()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        log.log("MEMORY WARNING, \(MemoryFootprint.summary())")
    }

    /// Light/dark follows the host text field when it says; otherwise the system setting.
    private func applyAppearance() {
        switch textDocumentProxy.keyboardAppearance {
        case .dark: overrideUserInterfaceStyle = .dark
        case .light: overrideUserInterfaceStyle = .light
        default: overrideUserInterfaceStyle = .unspecified
        }
    }

    // MARK: Model

    private func modelImported(_ result: String) {
        log.log(result)
        log.log("after import, \(MemoryFootprint.summary())")
        let service = InkRecognitionService()
        self.service = service
        for l in InkLanguage.allCases { log.log("isModelDownloaded(\(l.rawValue)) = \(service.isDownloaded(l))") }
        Task { await warmUp(service) }
    }

    /// Loads the model with a tiny dummy stroke, so the first real word is fast and the memory
    /// number with the model loaded is in the log. If ML Kit says "not downloaded", try anyway.
    private func warmUp(_ service: InkRecognitionService) async {
        let downloaded = service.isDownloaded(language)
        var points: [InkPoint] = []
        for i in 0..<12 {
            let x = CGFloat(10 + i * 4)
            let y = CGFloat(30 + (i % 3) * 6)
            points.append(InkPoint(x: x, y: y, t: Double(i) / 100))
        }
        let dummy = InkStroke(points: points, touchType: .direct)
        let started = Date()
        do {
            _ = try await service.recognize([dummy], language: language, maxResults: Self.candidateCount,
                                            requireDownloaded: downloaded)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if !downloaded { skipDownloadCheck = true }
            log.log("warm-up \(language.rawValue) OK in \(ms) ms (downloaded flag \(downloaded)), \(MemoryFootprint.summary())")
            setStatus(readyStatus())
        } catch {
            log.log("warm-up \(language.rawValue) FAILED (downloaded flag \(downloaded)): \(error)")
            log.log("ML Kit folder now:\n\(ModelSharing.localTree())")
            setStatus("model not available: open GreekInk › Setup")
        }
        if !canvas.strokes.isEmpty { scheduleCommit() }
    }

    private func readyStatus() -> String {
        "\(language.rawValue) · \(MemoryFootprint.summary().replacingOccurrences(of: "memory: ", with: ""))"
    }

    // MARK: Writing → text

    private func scheduleCommit() {
        pauseTask?.cancel()
        guard !canvas.strokes.isEmpty else { return }
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            await self?.recognizeAndCommit(trigger: "pause")
        }
    }

    /// Recognises the ink on the strip and inserts the top candidate. Calls run one at a time.
    private func recognizeAndCommit(trigger: String) async {
        let previous = recognition
        let task = Task { [weak self] in
            await previous?.value
            await self?.performRecognition(trigger: trigger)
        }
        recognition = task
        await task.value
    }

    private func performRecognition(trigger: String) async {
        let strokes = canvas.strokes
        guard !strokes.isEmpty else { return }
        guard let service else { setStatus("loading model…"); return }
        let preContext = Self.preContext(before: textDocumentProxy.documentContextBeforeInput ?? "")
        let area = canvas.bounds.size
        let started = Date()
        do {
            let result = try await service.recognize(strokes, language: language, preContext: preContext,
                                                     writingArea: area, maxResults: Self.candidateCount,
                                                     requireDownloaded: !skipDownloadCheck)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            // Strokes written while recognition ran stay on the strip for the next word.
            if canvas.strokes.count >= strokes.count { canvas.removeFirstStrokes(strokes.count) } else { canvas.clear() }
            let points = strokes.reduce(0) { $0 + $1.points.count }
            // Quoted, so leading spaces from ML Kit's word-break logic show up in the log.
            let raw = result.map { "\"\($0.text)\"" }.joined(separator: " / ")
            log.log("recognize \(trigger) \(language.rawValue): \(ms) ms, \(strokes.count) strokes, \(points) points, "
                    + "pre-context \"\(preContext)\", candidates: \(raw), \(MemoryFootprint.summary())")
            let texts = Self.cleaned(result.map(\.text))
            guard let top = texts.first else { setStatus("nothing recognised"); return }
            insertWord(top)
            lastCommit = Commit(text: top, alternatives: texts)
            showCandidates(texts, selected: top)
            setStatus(readyStatus())
        } catch {
            log.log("recognize \(trigger) FAILED: \(error)")
            setStatus("error: \(error.localizedDescription)")
        }
    }

    /// The text ML Kit sees before the ink: the last 20 characters (ML Kit's limit) of what is
    /// before the cursor, plus the space `insertWord` is about to add. With the space, ML Kit
    /// treats the ink as a new word; it still gets the sentence so far as context.
    static func preContext(before: String) -> String {
        let text = needsSpace(before: before, word: "a") ? before + " " : before
        return String(text.suffix(20))
    }

    /// Candidates without surrounding spaces (ML Kit may add a leading one after pre-context),
    /// empty and duplicate entries removed, order kept.
    static func cleaned(_ texts: [String]) -> [String] {
        var seen = Set<String>()
        return texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Inserts `word` with a space before it unless the cursor is at the start, after a space,
    /// after an opening bracket/quote, or the word starts with closing punctuation.
    private func insertWord(_ word: String) {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        textDocumentProxy.insertText(Self.needsSpace(before: before, word: word) ? " " + word : word)
    }

    static func needsSpace(before: String, word: String) -> Bool {
        guard let last = before.last, let first = word.first else { return false }
        if last.isWhitespace || "([{«“‘\"'".contains(last) { return false }
        // Greek question mark is ";" (or U+037E), ano teleia "·" (or U+0387).
        if ".,;:!?)]}»”’…·\u{037E}\u{0387}".contains(first) { return false }
        return true
    }

    /// Swaps the last inserted word for an alternative, if the text before the cursor still ends with it.
    private func replaceLastCommit(with alternative: String) {
        guard var commit = lastCommit, alternative != commit.text else { return }
        if let before = textDocumentProxy.documentContextBeforeInput, !before.hasSuffix(commit.text) {
            log.log("replace skipped: text before cursor no longer ends with “\(commit.text)”")
            clearCandidates()
            return
        }
        for _ in 0..<commit.text.count { textDocumentProxy.deleteBackward() }
        textDocumentProxy.insertText(alternative)
        log.log("replaced “\(commit.text)” with “\(alternative)”")
        commit.text = alternative
        lastCommit = commit
        showCandidates(commit.alternatives, selected: alternative)
    }

    // MARK: Keys

    @objc private func spaceTapped() {
        Task {
            await recognizeAndCommit(trigger: "space")
            textDocumentProxy.insertText(" ")
            clearCandidates()
        }
    }

    @objc private func returnTapped() {
        Task {
            await recognizeAndCommit(trigger: "return")
            textDocumentProxy.insertText("\n")
            clearCandidates()
        }
    }

    @objc private func deleteDown() {
        deleteOnce()
        deleteRepeat?.invalidate()
        deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                MainActor.assumeIsolated { self?.deleteOnce() }
            }
        }
    }

    @objc private func deleteUp() {
        deleteRepeat?.invalidate()
        deleteRepeat = nil
    }

    // MARK: Scribble to delete

    /// A zigzag scribble is a command, not ink: with other ink on the strip it erases that ink,
    /// on an empty strip it deletes the last word in the text.
    private func strokeEnded() {
        guard let last = canvas.strokes.last else { scheduleCommit(); return }
        let verdict = ScribbleDetector.check(last)
        log.log("stroke: \(last.points.count) points, \(verdict.summary)")
        guard verdict.isScribble else { scheduleCommit(); return }
        pauseTask?.cancel()
        if canvas.strokes.count > 1 {
            log.log("scribble: erased \(canvas.strokes.count - 1) strokes of ink")
            canvas.clear()
        } else {
            canvas.clear()
            deleteLastWord()
        }
    }

    /// Deletes the word before the cursor and the space before it. Uses the last inserted word
    /// when the text still ends with it, otherwise whatever word precedes the cursor.
    private func deleteLastWord() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        var count: Int
        if let commit = lastCommit, before.hasSuffix(commit.text) {
            count = commit.text.count
        } else {
            let trimmed = before.reversed().drop { $0.isWhitespace }
            let trailingSpaces = before.count - trimmed.count
            count = trailingSpaces + trimmed.prefix { !$0.isWhitespace }.count
        }
        // Also remove one space in front of the word (the auto space), if there is one.
        let rest = before.dropLast(count)
        if rest.last == " " { count += 1 }
        guard count > 0 else { log.log("scribble: nothing to delete"); return }
        for _ in 0..<count { textDocumentProxy.deleteBackward() }
        log.log("scribble: deleted \(count) characters (“\(before.suffix(count))”)")
        clearCandidates()
    }

    /// With ink on the strip, backspace removes the last stroke; otherwise one character.
    private func deleteOnce() {
        if !canvas.strokes.isEmpty {
            pauseTask?.cancel()
            canvas.undoLastStroke()
            scheduleCommit()
        } else {
            textDocumentProxy.deleteBackward()
            clearCandidates()
        }
    }

    @objc private func languageTapped() {
        language = language == .greek ? .english : .greek
        UserDefaults.standard.set(language.rawValue, forKey: InkLanguage.defaultsKey)
        updateLanguageKey()
        log.log("language → \(language.rawValue)")
        if let service, !service.isDownloaded(language), !skipDownloadCheck {
            setStatus("\(language.label) model not shared: download it in GreekInk")
        } else {
            setStatus(readyStatus())
        }
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard let text = sender.configuration?.title else { return }
        replaceLastCommit(with: text)
    }

    // MARK: UI

    private func buildUI() {
        view.backgroundColor = .secondarySystemBackground

        candidateStack.axis = .horizontal
        candidateStack.spacing = 6
        candidateStack.distribution = .fillEqually
        for _ in 0..<Self.candidateCount {
            var config = UIButton.Configuration.plain()
            config.titleLineBreakMode = .byTruncatingTail
            let b = UIButton(configuration: config)
            b.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            b.isHidden = true
            candidateButtons.append(b)
            candidateStack.addArrangedSubview(b)
        }

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .right
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let candidateRow = UIStackView(arrangedSubviews: [candidateStack, statusLabel])
        candidateRow.spacing = 8

        canvas.layer.cornerRadius = 10
        canvas.layer.borderWidth = 1
        canvas.layer.borderColor = UIColor.separator.cgColor
        canvas.onStrokeBegan = { [weak self] in self?.pauseTask?.cancel() }
        canvas.onStrokeEnded = { [weak self] in self?.strokeEnded() }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (vc: Self, _) in
            vc.canvas.layer.borderColor = UIColor.separator.cgColor
        }

        globeKey = key(image: "globe")
        globeKey.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        languageKey = key(title: "")
        languageKey.addTarget(self, action: #selector(languageTapped), for: .touchUpInside)
        updateLanguageKey()
        let space = key(title: "space", style: .white)
        space.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        let delete = key(image: "delete.left")
        delete.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        delete.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        let enter = key(image: "return")
        enter.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)

        let keyRow = UIStackView(arrangedSubviews: [globeKey, languageKey, space, delete, enter])
        keyRow.spacing = 8

        let column = UIStackView(arrangedSubviews: [candidateRow, canvas, keyRow])
        column.axis = .vertical
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            candidateRow.heightAnchor.constraint(equalToConstant: 40),
            keyRow.heightAnchor.constraint(equalToConstant: 48),
            globeKey.widthAnchor.constraint(equalToConstant: 64),
            languageKey.widthAnchor.constraint(equalToConstant: 80),
            delete.widthAnchor.constraint(equalToConstant: 88),
            enter.widthAnchor.constraint(equalToConstant: 110),
        ])
    }

    private enum KeyStyle { case gray, white }

    private func key(title: String? = nil, image: String? = nil, style: KeyStyle = .gray) -> UIButton {
        var config: UIButton.Configuration = style == .white ? .filled() : .gray()
        if style == .white {
            config.baseBackgroundColor = .systemBackground
            config.baseForegroundColor = .label
        }
        config.title = title
        if let image { config.image = UIImage(systemName: image) }
        config.cornerStyle = .medium
        return UIButton(configuration: config)
    }

    private func updateLanguageKey() {
        languageKey.configuration?.title = language == .greek ? "ΕΛ" : "EN"
    }

    private func showCandidates(_ texts: [String], selected: String) {
        for (i, b) in candidateButtons.enumerated() {
            guard i < texts.count else { b.isHidden = true; continue }
            var config: UIButton.Configuration = texts[i] == selected ? .tinted() : .plain()
            config.title = texts[i]
            config.titleLineBreakMode = .byTruncatingTail
            config.cornerStyle = .medium
            b.configuration = config
            b.isHidden = false
        }
    }

    private func clearCandidates() {
        lastCommit = nil
        candidateButtons.forEach { $0.isHidden = true }
    }

    private func setStatus(_ text: String) {
        statusLabel.text = text
    }
}
