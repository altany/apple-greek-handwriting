import UIKit

/// One sampled touch point. Coordinates are view points; `t` is the touch timestamp in seconds.
struct InkPoint {
    var x: CGFloat
    var y: CGFloat
    var t: TimeInterval
}

/// One pen-down to pen-up movement.
struct InkStroke {
    var points: [InkPoint]
    var touchType: UITouch.TouchType
}
