import UIKit

/// Minimal drawing surface for Phase 0: proves that Pencil and finger touches
/// reach a keyboard extension and that drawing is smooth. Not the real canvas.
final class InkTestView: UIView {
    var onTouch: ((UITouch.TouchType) -> Void)?

    private let path = UIBezierPath()
    private let shape = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .systemBackground
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        shape.strokeColor = UIColor.label.cgColor
        shape.fillColor = nil
        shape.lineWidth = 3
        shape.lineCap = .round
        shape.lineJoin = .round
        layer.addSublayer(shape)
        path.lineWidth = 3
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        shape.frame = bounds
        shape.strokeColor = UIColor.label.cgColor
        layer.borderColor = UIColor.separator.cgColor
    }

    func clear() {
        path.removeAllPoints()
        shape.path = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        onTouch?(t.type)
        path.move(to: t.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        // Coalesced touches = every sample the Pencil produced, not just one per frame.
        let samples = event?.coalescedTouches(for: t) ?? [t]
        for s in samples { path.addLine(to: s.location(in: self)) }
        shape.path = path.cgPath
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesMoved(touches, with: event)
    }
}
