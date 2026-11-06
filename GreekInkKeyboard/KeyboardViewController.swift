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
    static let keyboardHeight: CGFloat = 340
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
    private struct Commit {
        var text: String
        var alternatives: [String]
        /// Top candidate of the other language (the EN/ΕΛ chip), added a moment later.
        var extra: String? = nil
        var extraLanguage: InkLanguage? = nil
    }
    private var lastCommit: Commit?

    /// The 123 key: digit keys in the row, and handwriting prefers digits.
    private var numberMode = false
    private let symbolRow = UIStackView()
    static let punctuation = [".", ",", ";", "·", "!", "?", ":", "'", "\"", "(", ")", "-"]
    static let numberKeys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", ".", ",", ":", "/", "-", "%"]

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
        "\(numberMode ? "123" : language.rawValue) · \(MemoryFootprint.summary().replacingOccurrences(of: "memory: ", with: ""))"
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
            let cleaned = Self.cleaned(result.map(\.text))
            let texts = numberMode ? Array(NumberMode.rank(cleaned).prefix(Self.candidateCount)) : cleaned
            guard let top = texts.first else { setStatus("nothing recognised"); return }
            insertWord(top)
            lastCommit = Commit(text: top, alternatives: texts)
            showCandidates(texts, selected: top)
            setStatus(readyStatus())
            // After the insert, so it never delays the word.
            await addOtherLanguageChip(strokes, preContext: preContext, area: area, inserted: top)
        } catch {
            log.log("recognize \(trigger) FAILED: \(error)")
            setStatus("error: \(error.localizedDescription)")
        }
    }

    /// Runs the other language's model (en while writing Greek, el while writing English) on the
    /// same strokes and shows its top candidate as an extra chip, so a Latin word inside Greek
    /// text needs no ΕΛ/EN switch. Skipped in number mode or when that model isn't shared.
    private func addOtherLanguageChip(_ strokes: [InkStroke], preContext: String, area: CGSize, inserted: String) async {
        guard !numberMode, let service else { return }
        let other: InkLanguage = language == .greek ? .english : .greek
        guard skipDownloadCheck || service.isDownloaded(other) else { return }
        let started = Date()
        do {
            let result = try await service.recognize(strokes, language: other, preContext: preContext,
                                                     writingArea: area, maxResults: 1,
                                                     requireDownloaded: !skipDownloadCheck)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            let text = Self.cleaned(result.map(\.text)).first
            log.log("other-language chip \(other.rawValue): \(ms) ms, \"\(text ?? "-")\", \(MemoryFootprint.summary())")
            // Only if the inserted word is still the one on screen and the chip adds something new.
            guard let text, var commit = lastCommit, commit.text == inserted,
                  !commit.alternatives.contains(text) else { return }
            commit.extra = text
            commit.extraLanguage = other
            lastCommit = commit
            showCandidates(commit.alternatives, selected: commit.text, extra: text, extraLanguage: other)
        } catch {
            log.log("other-language chip \(other.rawValue) FAILED: \(error)")
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
        let continuesNumber = numberMode && Self.continuesNumber(before: before, word: word)
        let space = !continuesNumber && Self.needsSpace(before: before, word: word)
        textDocumentProxy.insertText(space ? " " + word : word)
    }

    /// Number mode: "20" then "26" makes "2026", "3." then "5" makes "3.5", "15:" then "30" makes "15:30".
    static func continuesNumber(before: String, word: String) -> Bool {
        guard let first = word.first, first.isNumber, let last = before.last else { return false }
        if last.isNumber { return true }
        let prev = before.dropLast().last
        return ".,:/-".contains(last) && prev?.isNumber == true
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
        showCandidates(commit.alternatives, selected: alternative, extra: commit.extra, extraLanguage: commit.extraLanguage)
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
        // A dot or speck (e.g. the Pencil touching down just before the zigzag) is not ink to
        // erase: if that is all there is, the strip counts as empty.
        let ink = canvas.strokes.dropLast().filter { !Self.isSpeck($0) }
        canvas.clear()
        if ink.isEmpty {
            deleteLastWord()
        } else {
            log.log("scribble: erased \(ink.count) strokes of ink")
        }
    }

    /// Smaller than 8 pt both ways: a dot or a stray touch, not writing worth keeping.
    static func isSpeck(_ stroke: InkStroke) -> Bool {
        let xs = stroke.points.map(\.x), ys = stroke.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return true }
        return maxX - minX < 8 && maxY - minY < 8
    }

    /// Deletes the word before the cursor and the space before it, on the current line only:
    /// it never deletes a line break or an attachment (Notes puts U+FFFC for those).
    private func deleteLastWord() {
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let stops: (Character) -> Bool = { $0.isNewline || $0 == "\u{FFFC}" }
        var count: Int
        if let commit = lastCommit, before.hasSuffix(commit.text) {
            count = commit.text.count
        } else {
            let trimmed = before.reversed().drop { $0 == " " || $0 == "\t" }
            let trailingSpaces = before.count - trimmed.count
            let word = trimmed.prefix { !$0.isWhitespace && !stops($0) }.count
            count = word == 0 ? 0 : trailingSpaces + word
        }
        guard count > 0 else { log.log("scribble: no word before the cursor on this line, nothing deleted"); return }
        // Also remove one space in front of the word (the auto space), if there is one.
        if before.dropLast(count).last == " " { count += 1 }
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
        for _ in 0..<(Self.candidateCount + 1) {   // + 1: the other-language chip
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

        symbolRow.spacing = 6
        symbolRow.distribution = .fill
        rebuildSymbolRow()

        let column = UIStackView(arrangedSubviews: [candidateRow, symbolRow, canvas, keyRow])
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
            symbolRow.heightAnchor.constraint(equalToConstant: 38),
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

    private func showCandidates(_ texts: [String], selected: String,
                                extra: String? = nil, extraLanguage: InkLanguage? = nil) {
        for (i, b) in candidateButtons.enumerated() {
            if i == Self.candidateCount {
                // Last slot: the other-language chip, labelled EN or ΕΛ.
                guard let extra else { b.isHidden = true; continue }
                var config: UIButton.Configuration = extra == selected ? .tinted() : .bordered()
                config.title = extra
                config.subtitle = extraLanguage == .greek ? "ΕΛ" : "EN"
                config.titleAlignment = .center
                config.titleLineBreakMode = .byTruncatingTail
                config.cornerStyle = .medium
                b.configuration = config
                b.isHidden = false
                continue
            }
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

    // MARK: Symbol row

    private func rebuildSymbolRow() {
        symbolRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let toggle = key(title: numberMode ? "αβγ" : "123")
        toggle.configuration?.titleLineBreakMode = .byClipping   // one line, never "α/β/γ" stacked
        toggle.addTarget(self, action: #selector(numberModeTapped), for: .touchUpInside)
        toggle.widthAnchor.constraint(equalToConstant: 72).isActive = true
        symbolRow.addArrangedSubview(toggle)
        var first: UIButton?
        for symbol in numberMode ? Self.numberKeys : Self.punctuation {
            var config = UIButton.Configuration.plain()
            config.title = symbol
            config.baseForegroundColor = .label
            config.background.backgroundColor = .tertiarySystemFill
            config.cornerStyle = .medium
            let b = UIButton(configuration: config)
            b.addTarget(self, action: #selector(symbolTapped(_:)), for: .touchUpInside)
            symbolRow.addArrangedSubview(b)
            // Symbol keys share the remaining width equally.
            if let first { b.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true } else { first = b }
        }
    }

    @objc private func numberModeTapped() {
        numberMode.toggle()
        rebuildSymbolRow()
        log.log("number mode \(numberMode ? "on" : "off")")
        setStatus(readyStatus())
    }

    /// Inserts ink waiting on the strip first, then the symbol with sensible spacing.
    @objc private func symbolTapped(_ sender: UIButton) {
        guard let symbol = sender.configuration?.title else { return }
        Task {
            await recognizeAndCommit(trigger: "symbol")
            let before = textDocumentProxy.documentContextBeforeInput ?? ""
            textDocumentProxy.insertText(Self.spaced(symbol, before: before))
            clearCandidates()
        }
    }

    /// Closing marks attach to the word before; "(" gets a space before it after a word;
    /// a quote closes after a word and opens otherwise; digits follow digits directly.
    static func spaced(_ symbol: String, before: String) -> String {
        guard let last = before.last else { return symbol }
        let afterWord = !last.isWhitespace && last != "(" && last != "\n"
        switch symbol {
        case "(":
            return afterWord ? " (" : "("
        case "'", "\"":
            return symbol
        default:
            if symbol.first?.isNumber == true {
                // A digit after a letter-word starts a new word; after a digit or symbol it continues.
                return last.isLetter ? " " + symbol : symbol
            }
            return symbol
        }
    }

    private func setStatus(_ text: String) {
        statusLabel.text = text
    }
}
