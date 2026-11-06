import CoreGraphics

/// Recognises a zigzag scribble (the "scratch it out" gesture) from one stroke.
///
/// ML Kit's iOS SDK (8.0.0) has no gesture classifier: its built-in model list holds only the
/// text languages plus emoji, shapes and autodraw. So this is a plain geometric test: a scribble
/// is wide, not tall, and sweeps back and forth across most of its width several times.
/// Letters can turn as often (up to 6 turns measured) but in short moves, so the test counts
/// long sweeps, not turns. Measured on the iPad: zigzags 104–175 pt wide, 35–58 pt tall, 4 turns;
/// letters up to 6 turns but short legs. The keyboard logs every verdict for further tuning.
enum ScribbleDetector {
    /// Sweeps covering at least `longLegFraction` of the stroke's width.
    static let minLongLegs = 3
    static let longLegFraction: CGFloat = 0.5
    static let minWidth: CGFloat = 60
    /// Height may be at most this fraction of the width (zigzags measured 0.25–0.56, a wide letter 0.61).
    static let maxHeightRatio: CGFloat = 0.6
    /// Horizontal moves shorter than this are noise, not a change of direction.
    static let minLeg: CGFloat = 6

    struct Verdict {
        let isScribble: Bool
        let reversals: Int
        let longLegs: Int
        let width: CGFloat
        let height: CGFloat
        var summary: String {
            "reversals \(reversals), long legs \(longLegs), \(Int(width))×\(Int(height)) pt → \(isScribble ? "SCRIBBLE" : "ink")"
        }
    }

    static func check(_ stroke: InkStroke) -> Verdict {
        let xs = stroke.points.map(\.x), ys = stroke.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return Verdict(isScribble: false, reversals: 0, longLegs: 0, width: 0, height: 0)
        }
        let width = maxX - minX, height = maxY - minY

        // Split the stroke into horizontal legs (runs in one direction), ignoring jitter shorter
        // than minLeg, and measure each leg from where it started to where it turned.
        var legs: [CGFloat] = []
        var direction: CGFloat = 0      // +1 right, -1 left, 0 unknown yet
        var legStart = xs[0], anchor = xs[0]
        for x in xs.dropFirst() {
            let dx = x - anchor
            if abs(dx) < minLeg { continue }
            let d: CGFloat = dx > 0 ? 1 : -1
            if direction != 0, d != direction {
                legs.append(abs(anchor - legStart))
                legStart = anchor
            }
            direction = d
            anchor = x
        }
        legs.append(abs(anchor - legStart))
        let reversals = max(0, legs.count - 1)
        let longLegs = legs.filter { $0 >= width * longLegFraction }.count

        let isScribble = longLegs >= minLongLegs && width >= minWidth && height <= width * maxHeightRatio
        return Verdict(isScribble: isScribble, reversals: reversals, longLegs: longLegs, width: width, height: height)
    }
}
