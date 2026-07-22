import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { exit(2) }

let side = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { exit(3) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

let backgroundRect = NSRect(x: 52, y: 52, width: 920, height: 920)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 220, yRadius: 220)
let gradient = NSGradient(
    starting: NSColor(red: 0.20, green: 0.30, blue: 0.98, alpha: 1),
    ending: NSColor(red: 0.05, green: 0.76, blue: 0.63, alpha: 1)
)!
gradient.draw(in: background, angle: -38)

NSColor.white.withAlphaComponent(0.16).setFill()
NSBezierPath(ovalIn: NSRect(x: 515, y: 500, width: 510, height: 510)).fill()

let card = NSBezierPath(roundedRect: NSRect(x: 220, y: 225, width: 584, height: 574), xRadius: 90, yRadius: 90)
NSColor.white.withAlphaComponent(0.96).setFill()
card.fill()

let bars: [(CGFloat, CGFloat)] = [(330, 170), (445, 270), (560, 215), (675, 365)]
for (x, height) in bars {
    let bar = NSBezierPath(roundedRect: NSRect(x: x, y: 325, width: 72, height: height), xRadius: 30, yRadius: 30)
    gradient.draw(in: bar, angle: 90)
}

let label = "API"
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 92, weight: .heavy),
    .foregroundColor: NSColor(red: 0.18, green: 0.25, blue: 0.52, alpha: 1),
    .kern: 6
]
let labelSize = label.size(withAttributes: attributes)
label.draw(
    at: NSPoint(x: (CGFloat(side) - labelSize.width) / 2, y: 672),
    withAttributes: attributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
