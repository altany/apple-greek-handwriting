import CoreGraphics

/// Recognises a zigzag scribble (the "scratch it out" gesture) from one stroke.
///
/// ML Kit's iOS SDK (8.0.0) has no gesture classifier: its built-in model list holds only the
/// text languages plus emoji, shapes and autodraw. So this is a plain geometric test: a scribble
/// is wide, not tall, and turns back and forth horizontally many times. Letters rarely reverse
/// direction more than 2–3 times in one stroke. Thresholds are first guesses; the keyboard logs
/// every decision so they can be tuned from real strokes.
enum ScribbleDetector {
    static let minReversals = 5
    static let minWidth: CGFloat = 50
    /// Height may be at most this fraction of the width.
    static let maxHeightRatio: CGFloat = 0.9
    /// Horizontal moves shorter than this are noise, not a change of direction.
    static let minLeg: CGFloat = 6

    struct Verdict {
        let isScribble: Bool
        let reversals: Int
        let width: CGFloat
        let height: CGFloat
        var summary: String {
            "reversals \(reversals), \(Int(width))×\(Int(height)) pt → \(isScribble ? "SCRIBBLE" : "ink")"
        }
    }

    static func check(_ stroke: InkStroke) -> Verdict {
        let xs = stroke.points.map(\.x), ys = stroke.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return Verdict(isScribble: false, reversals: 0, width: 0, height: 0)
        }
        let width = maxX - minX, height = maxY - minY

        // Count horizontal direction changes, ignoring jitter shorter than minLeg.
        var reversals = 0
        var direction: CGFloat = 0      // +1 right, -1 left, 0 unknown yet
        var anchor = xs[0]              // x where the current leg started
        for x in xs.dropFirst() {
            let dx = x - anchor
            if abs(dx) < minLeg { continue }
            let d: CGFloat = dx > 0 ? 1 : -1
            if direction != 0, d != direction { reversals += 1 }
            direction = d
            anchor = x
        }

        let isScribble = reversals >= minReversals && width >= minWidth && height <= width * maxHeightRatio
        return Verdict(isScribble: isScribble, reversals: reversals, width: width, height: height)
    }
}
