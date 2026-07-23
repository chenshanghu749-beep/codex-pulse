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

let tileRect = NSRect(x: 62, y: 62, width: 900, height: 900)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 218, yRadius: 218)
NSColor(calibratedWhite: 0.965, alpha: 1).setFill()
tile.fill()
NSColor.black.withAlphaComponent(0.1).setStroke()
tile.lineWidth = 8
tile.stroke()

let core = NSBezierPath(ovalIn: NSRect(x: 192, y: 192, width: 640, height: 640))
NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
core.fill()

let orbit = NSBezierPath()
orbit.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 225, startAngle: 42, endAngle: 318, clockwise: false)
NSColor.white.setStroke()
orbit.lineWidth = 76
orbit.lineCapStyle = .round
orbit.stroke()

let pulse = NSBezierPath()
pulse.move(to: NSPoint(x: 250, y: 500))
pulse.line(to: NSPoint(x: 372, y: 500))
pulse.line(to: NSPoint(x: 430, y: 612))
pulse.line(to: NSPoint(x: 503, y: 388))
pulse.line(to: NSPoint(x: 570, y: 540))
pulse.line(to: NSPoint(x: 637, y: 500))
pulse.line(to: NSPoint(x: 774, y: 500))
NSColor.white.setStroke()
pulse.lineWidth = 42
pulse.lineJoinStyle = .round
pulse.lineCapStyle = .round
pulse.stroke()

let statusDot = NSBezierPath(ovalIn: NSRect(x: 690, y: 650, width: 96, height: 96))
NSColor.white.setFill()
statusDot.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(4) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
