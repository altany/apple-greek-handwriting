import UIKit

/// Drawing surface shared by the app and the keyboard. Records strokes with timestamps
/// (what ML Kit needs) and renders them. Pencil and finger both work; coalesced touches
/// give every Pencil sample, not one per frame.
///
/// Palm handling: multi-touch stays enabled so a Pencil touch is still delivered while the
/// writing hand rests on the glass. A Pencil touch always wins over a finger/palm stroke that
/// started first, extra touches during a stroke are ignored, and finger touches that start
/// shortly after Pencil contact are treated as the palm and ignored.
final class InkCanvasView: UIView {

    var onStrokeBegan: (() -> Void)?
    var onStrokeEnded: (() -> Void)?
    /// Diagnostics only: one line per touch began/ended/cancelled, with what the view decided.
    var onTouchEvent: ((String) -> Void)?

    var lineWidth: CGFloat = 3 { didSet { committedLayer.lineWidth = lineWidth; activeLayer.lineWidth = lineWidth } }
    var showsGuideline = true { didSet { setNeedsLayout() } }
    /// Finger touches that start within this many seconds of the last Pencil contact are ignored.
    var palmGracePeriod: TimeInterval = 1.5
    /// Finger touches wider than this (points) are treated as a resting palm and ignored.
    /// Measured on the iPad Air: fingertip ~20–25, palm 52–62. iPadOS reports 0 for the Pencil.
    var palmRadius: CGFloat = 40

    private(set) var strokes: [InkStroke] = []

    private var activeTouch: UITouch?
    private var activePoints: [InkPoint] = []
    private var activePath = UIBezierPath()
    private var lastPencilTimestamp: TimeInterval = -.infinity

    private let committedPath = UIBezierPath()
    private let committedLayer = CAShapeLayer()
    private let activeLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Must stay on: with it off, a palm that lands first swallows every later Pencil touch.
        isMultipleTouchEnabled = true
        backgroundColor = .systemBackground
        for layer in [committedLayer, activeLayer] {
            layer.fillColor = nil
            layer.lineWidth = lineWidth
            layer.lineCap = .round
            layer.lineJoin = .round
        }
        guideLayer.fillColor = nil
        guideLayer.lineWidth = 1
        guideLayer.lineDashPattern = [6, 6]
        self.layer.addSublayer(guideLayer)
        self.layer.addSublayer(committedLayer)
        self.layer.addSublayer(activeLayer)
        applyColors()
        // Re-resolve dynamic colours when light/dark changes (CALayer colours don't update themselves).
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in view.applyColors() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for layer in [committedLayer, activeLayer, guideLayer] { layer.frame = bounds }
        let guide = UIBezierPath()
        if showsGuideline {
            let y = (bounds.height * 0.68).rounded()
            guide.move(to: CGPoint(x: 12, y: y))
            guide.addLine(to: CGPoint(x: bounds.width - 12, y: y))
        }
        guideLayer.path = guide.cgPath
    }

    private func applyColors() {
        committedLayer.strokeColor = UIColor.label.cgColor
        activeLayer.strokeColor = UIColor.label.cgColor
        guideLayer.strokeColor = UIColor.separator.cgColor
    }

    // MARK: Public

    func clear() {
        strokes.removeAll()
        committedPath.removeAllPoints()
        committedLayer.path = nil
        activeLayer.path = nil
        activePoints.removeAll()
        activeTouch = nil
    }

    func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        committedPath.removeAllPoints()
        for stroke in strokes { committedPath.append(Self.path(for: stroke)) }
        committedLayer.path = committedPath.cgPath
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let active = activeTouch {
                if touch.type == .pencil, active.type != .pencil {
                    report("began", touch, "pencil replaces \(Self.name(active.type)) stroke")
                    discardActiveStroke()
                } else {
                    report("began", touch, "ignored, \(Self.name(active.type)) stroke in progress")
                    continue
                }
            } else if touch.type != .pencil, touch.timestamp - lastPencilTimestamp < palmGracePeriod {
                report("began", touch, "ignored, palm grace after pencil")
                continue
            } else if touch.type == .direct, touch.majorRadius > palmRadius {
                report("began", touch, "ignored, too wide for a finger")
                continue
            } else {
                report("began", touch, "stroke starts")
            }
            beginStroke(with: touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        if touch.type == .direct, touch.majorRadius > palmRadius {
            // A finger that flattens into a palm mid-stroke.
            report("moved", touch, "discarded, grew too wide for a finger")
            discardActiveStroke()
            return
        }
        notePencil(touch)
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let p = point(from: sample)
            activePoints.append(p)
            activePath.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        activeLayer.path = activePath.cgPath
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            touches.forEach { report("ended", $0, "not the active touch") }
            return
        }
        notePencil(touch)
        let p = point(from: touch)
        activePoints.append(p)
        activePath.addLine(to: CGPoint(x: p.x, y: p.y))
        report("ended", touch, "stroke committed, \(activePoints.count) points")
        commitActiveStroke(touchType: touch.type)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else {
            touches.forEach { report("cancelled", $0, "not the active touch") }
            return
        }
        // The system cancels touches it decided were a palm or a gesture: drop, don't commit.
        report("cancelled", touch, "stroke discarded")
        discardActiveStroke()
    }

    private func beginStroke(with touch: UITouch) {
        activeTouch = touch
        notePencil(touch)
        let p = point(from: touch)
        activePoints = [p]
        activePath = UIBezierPath()
        activePath.move(to: CGPoint(x: p.x, y: p.y))
        onStrokeBegan?()
    }

    private func commitActiveStroke(touchType: UITouch.TouchType) {
        if activePoints.count >= 1 {
            strokes.append(InkStroke(points: activePoints, touchType: touchType))
            committedPath.append(activePath)
            committedLayer.path = committedPath.cgPath
        }
        activeLayer.path = nil
        activePoints.removeAll()
        activeTouch = nil
        onStrokeEnded?()
    }

    /// Drops the stroke in progress without recording it. Still reports "ended" so the owner
    /// can reschedule recognition it paused when the stroke began.
    private func discardActiveStroke() {
        activeLayer.path = nil
        activePoints.removeAll()
        activeTouch = nil
        onStrokeEnded?()
    }

    private func notePencil(_ touch: UITouch) {
        if touch.type == .pencil { lastPencilTimestamp = touch.timestamp }
    }

    private func report(_ phase: String, _ touch: UITouch, _ decision: String) {
        onTouchEvent?("\(phase) \(Self.name(touch.type)) r=\(Int(touch.majorRadius)) → \(decision)")
    }

    static func name(_ type: UITouch.TouchType) -> String {
        switch type {
        case .direct: return "finger"
        case .pencil: return "pencil"
        case .indirect: return "indirect"
        case .indirectPointer: return "pointer"
        @unknown default: return "other(\(type.rawValue))"
        }
    }

    private func point(from touch: UITouch) -> InkPoint {
        let loc = touch.preciseLocation(in: self)
        return InkPoint(x: loc.x, y: loc.y, t: touch.timestamp)
    }

    private static func path(for stroke: InkStroke) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = stroke.points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for p in stroke.points.dropFirst() { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        if stroke.points.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y)) } // dot
        return path
    }
}
