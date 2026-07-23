import AppKit
import Foundation

@main
enum StatusIconPreview {
static func main() throws {
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: StatusIconPreview <output.png>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvasSize = NSSize(width: 760, height: 450)
let image = NSImage(size: canvasSize, flipped: false) { rect in
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    rect.fill()

    let title = NSAttributedString(
        string: "Codex Pulse · 状态图标主题",
        attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
        ]
    )
    title.draw(at: NSPoint(x: 32, y: 402))

    for (index, style) in StatusIconStyle.allCases.enumerated() {
        let y = CGFloat(334 - index * 72)
        let label = NSAttributedString(
            string: style.displayName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1)
            ]
        )
        label.draw(in: NSRect(x: 34, y: y + 9, width: 150, height: 25))

        let stripRect = NSRect(x: 184, y: y, width: 540, height: 48)
        let strip = NSBezierPath(roundedRect: stripRect, xRadius: 14, yRadius: 14)
        NSColor(calibratedWhite: 0.10, alpha: 0.94).setFill()
        strip.fill()

        for (signalIndex, signal) in TrafficSignal.allCases.enumerated() {
            let icon = StatusIconRenderer.image(style: style, active: signal)
            let scale: CGFloat = 1.7
            let iconSize = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            let centerX = CGFloat(270 + signalIndex * 175)
            let target = NSRect(
                x: centerX - iconSize.width / 2,
                y: y + (48 - iconSize.height) / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            icon.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render preview\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
print(outputURL.path)
}
}
