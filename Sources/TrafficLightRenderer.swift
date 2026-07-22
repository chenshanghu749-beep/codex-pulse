import AppKit

enum TrafficSignal: CaseIterable {
    case red
    case yellow
    case green

    var color: NSColor {
        switch self {
        case .red: return .systemRed
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        }
    }
}

enum TrafficLightRenderer {
    static func image(active: TrafficSignal) -> NSImage {
        let size = NSSize(width: 56, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let housing = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8.5, yRadius: 8.5)
            NSColor.black.withAlphaComponent(0.88).setFill()
            housing.fill()
            NSColor.white.withAlphaComponent(0.14).setStroke()
            housing.lineWidth = 1
            housing.stroke()

            let signals = TrafficSignal.allCases
            let diameter: CGFloat = 11
            let spacing: CGFloat = 5.5
            let totalWidth = diameter * 3 + spacing * 2
            let startX = (rect.width - totalWidth) / 2
            let y = (rect.height - diameter) / 2

            for (index, signal) in signals.enumerated() {
                let lampRect = NSRect(
                    x: startX + CGFloat(index) * (diameter + spacing),
                    y: y,
                    width: diameter,
                    height: diameter
                )
                let lamp = NSBezierPath(ovalIn: lampRect)
                signal.color.withAlphaComponent(signal == active ? 1 : 0.18).setFill()
                lamp.fill()

                if signal == active {
                    NSColor.white.withAlphaComponent(0.45).setStroke()
                    lamp.lineWidth = 0.8
                    lamp.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "红黄绿状态灯"
        return image
    }
}
