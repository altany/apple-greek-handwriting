// Renders the 1024×1024 app icon: a white handwritten-style Greek "α" with an ink stroke
// under it, on a teal-to-purple gradient. Run: swift scripts/make-icon.swift <output.png>
import AppKit

let size = 1024.0
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Background: teal (top left) to vivid purple (bottom right). Full bleed; iOS rounds the corners.
let colors = [NSColor(red: 0.00, green: 0.86, blue: 0.76, alpha: 1).cgColor,
              NSColor(red: 0.30, green: 0.42, blue: 0.98, alpha: 1).cgColor,
              NSColor(red: 0.66, green: 0.16, blue: 0.94, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// The letter: Georgia Italic has proper Greek glyphs.
let font = NSFont(name: "Georgia-Italic", size: 820) ?? NSFont.systemFont(ofSize: 820)
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
let text = NSAttributedString(string: "α", attributes: attrs)
let bounds = text.boundingRect(with: NSSize(width: size, height: size), options: [.usesDeviceMetrics])
// Letter body centred a little above the middle, leaving room for the ink line.
text.draw(at: NSPoint(x: (size - bounds.width) / 2 - bounds.minX, y: 215 - bounds.minY))

// Ink stroke under it, like a pen line: warm gold, round ends, a gentle wave.
let ink = NSBezierPath()
ink.move(to: NSPoint(x: 215, y: 280))
ink.curve(to: NSPoint(x: 515, y: 268), controlPoint1: NSPoint(x: 310, y: 235), controlPoint2: NSPoint(x: 425, y: 305))
ink.curve(to: NSPoint(x: 815, y: 295), controlPoint1: NSPoint(x: 605, y: 230), controlPoint2: NSPoint(x: 715, y: 263))
ink.lineWidth = 34
ink.lineCapStyle = .round
NSColor(red: 1.0, green: 0.78, blue: 0.30, alpha: 1).setStroke()
ink.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
