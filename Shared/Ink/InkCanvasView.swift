import UIKit

/// Drawing surface shared by the app and the keyboard. Records strokes with timestamps
/// (what ML Kit needs) and renders them. Pencil and finger both work; coalesced touches
/// give every Pencil sample, not one per frame.
final class InkCanvasView: UIView {

    var onStrokeBegan: (() -> Void)?
    var onStrokeEnded: (() -> Void)?

    var lineWidth: CGFloat = 3 { didSet { committedLayer.lineWidth = lineWidth; activeLayer.lineWidth = lineWidth } }
    var showsGuideline = true { didSet { setNeedsLayout() } }

    private(set) var strokes: [InkStroke] = []

    private var activeTouch: UITouch?
    private var activePoints: [InkPoint] = []
    private var activePath = UIBezierPath()

    private let committedPath = UIBezierPath()
    private let committedLayer = CAShapeLayer()
    private let activeLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
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
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        let p = point(from: touch)
        activePoints = [p]
        activePath = UIBezierPath()
        activePath.move(to: CGPoint(x: p.x, y: p.y))
        onStrokeBegan?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch == activeTouch else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let p = point(from: sample)
            activePoints.append(p)
            activePath.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        activeLayer.path = activePath.cgPath
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch == activeTouch else { return }
        let p = point(from: touch)
        activePoints.append(p)
        activePath.addLine(to: CGPoint(x: p.x, y: p.y))
        commitActiveStroke(touchType: touch.type)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch == activeTouch else { return }
        commitActiveStroke(touchType: touch.type)
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
