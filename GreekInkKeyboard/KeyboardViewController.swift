import UIKit

/// Phase 0 keyboard: proves signing, App Group access, text insertion,
/// the globe key, Pencil touches, and shows real memory numbers.
final class KeyboardViewController: UIInputViewController {

    private let statusLabel = UILabel()
    private let inkView = InkTestView()
    private var nextKeyboardButton: UIButton!
    private var heightConstraint: NSLayoutConstraint?
    private var lastResult = "—"
    private var pencilTouches = 0
    private var fingerTouches = 0

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        refreshStatus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // A keyboard sets its own height with a constraint on its root view.
        if heightConstraint == nil {
            let c = view.heightAnchor.constraint(equalToConstant: 300)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
        applyAppearance()
        refreshStatus()
    }

    override func viewWillLayoutSubviews() {
        // Apple requires the globe key only when the system says so (e.g. not on iPad with a hardware keyboard bar).
        nextKeyboardButton.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        applyAppearance()
    }

    /// Light/dark follows the host text field, not the system setting.
    private func applyAppearance() {
        overrideUserInterfaceStyle = textDocumentProxy.keyboardAppearance == .dark ? .dark : .light
    }

    // MARK: UI

    private func buildUI() {
        view.backgroundColor = .secondarySystemBackground

        statusLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.numberOfLines = 0
        statusLabel.textColor = .label

        nextKeyboardButton = key("🌐")
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        let row1 = UIStackView(arrangedSubviews: [
            nextKeyboardButton,
            key("γεια", #selector(insertSample)),
            key("space", #selector(insertSpace)),
            key("⌫", #selector(backspace)),
            key("return", #selector(insertReturn)),
        ])
        let row2 = UIStackView(arrangedSubviews: [
            key("write ping", #selector(writePing)),
            key("read ping", #selector(readPing)),
            key("clear ink", #selector(clearInk)),
            key("refresh", #selector(refresh)),
        ])
        for row in [row1, row2] {
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
        }

        inkView.onTouch = { [weak self] type in
            guard let self else { return }
            if type == .pencil { self.pencilTouches += 1 } else { self.fingerTouches += 1 }
            self.refreshStatus()
        }

        let column = UIStackView(arrangedSubviews: [statusLabel, inkView, row1, row2])
        column.axis = .vertical
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)

        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            column.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            inkView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            row1.heightAnchor.constraint(equalToConstant: 40),
            row2.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    private func key(_ title: String, _ action: Selector? = nil) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.cornerStyle = .medium
        let b = UIButton(configuration: config)
        if let action { b.addTarget(self, action: action, for: .touchUpInside) }
        return b
    }

    private func refreshStatus() {
        statusLabel.text = """
        GreekInk keyboard — Phase 0   Full Access: \(hasFullAccess)
        group: \(AppGroup.identifier)
        container: \(AppGroup.containerURL?.path ?? "nil (not granted)")
        \(MemoryFootprint.summary())
        touches: pencil \(pencilTouches), finger \(fingerTouches)
        last: \(lastResult)
        """
    }

    // MARK: Actions

    @objc private func insertSample() { textDocumentProxy.insertText("γεια") }
    @objc private func insertSpace() { textDocumentProxy.insertText(" ") }
    @objc private func insertReturn() { textDocumentProxy.insertText("\n") }
    @objc private func backspace() { textDocumentProxy.deleteBackward() }
    @objc private func clearInk() { inkView.clear() }
    @objc private func refresh() { refreshStatus() }

    @objc private func writePing() {
        lastResult = AppGroup.writePing(from: "keyboard")
        refreshStatus()
    }

    @objc private func readPing() {
        lastResult = AppGroup.readPing()
        refreshStatus()
    }
}
