import AppKit

enum TrafficSignal: CaseIterable, Equatable {
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

enum StatusIconStyle: String, CaseIterable {
    case trafficLight
    case lightBulb
    case topHatMascot
    case basketballMascot
    case statusRing

    var displayName: String {
        switch self {
        case .trafficLight: return "经典红绿灯"
        case .lightBulb: return "灵感灯泡"
        case .topHatMascot: return "礼帽伙伴"
        case .basketballMascot: return "篮球伙伴"
        case .statusRing: return "状态圆环"
        }
    }
}

enum StatusIconPreference {
    private static let key = "statusIconStyle"

    static var selected: StatusIconStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let style = StatusIconStyle(rawValue: raw) else { return .trafficLight }
            return style
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

enum StatusIconRenderer {
    static func image(style: StatusIconStyle, active: TrafficSignal, frame: Int = 0) -> NSImage {
        let image: NSImage
        switch style {
        case .trafficLight: image = trafficLight(active: active)
        case .lightBulb: image = lightBulb(active: active)
        case .topHatMascot: image = topHatMascot(active: active, frame: frame)
        case .basketballMascot: image = basketballMascot(active: active, frame: frame)
        case .statusRing: image = statusRing(active: active)
        }
        image.isTemplate = false
        image.accessibilityDescription = "\(style.displayName)状态图标"
        return image
    }

    static func blended(from: NSImage, to: NSImage, progress: CGFloat) -> NSImage {
        let fraction = min(1, max(0, progress))
        let size = NSSize(width: max(from.size.width, to.size.width), height: max(from.size.height, to.size.height))
        return NSImage(size: size, flipped: false) { _ in
            let oldRect = NSRect(x: (size.width - from.size.width) / 2, y: 0, width: from.size.width, height: from.size.height)
            let newRect = NSRect(x: (size.width - to.size.width) / 2, y: 0, width: to.size.width, height: to.size.height)
            from.draw(in: oldRect, from: .zero, operation: .sourceOver, fraction: 1 - fraction)
            to.draw(in: newRect, from: .zero, operation: .sourceOver, fraction: fraction)
            return true
        }
    }

    private static func canvas(width: CGFloat, drawing: @escaping (NSRect) -> Void) -> NSImage {
        NSImage(size: NSSize(width: width, height: 18), flipped: false) { rect in
            drawing(rect)
            return true
        }
    }

    private static func trafficLight(active: TrafficSignal) -> NSImage {
        canvas(width: 54) { rect in
            let housing = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 1), xRadius: 8, yRadius: 8)
            NSColor.labelColor.withAlphaComponent(0.92).setFill()
            housing.fill()

            let diameter: CGFloat = 10
            let spacing: CGFloat = 6
            let startX = (rect.width - diameter * 3 - spacing * 2) / 2
            for (index, signal) in TrafficSignal.allCases.enumerated() {
                let lamp = NSBezierPath(ovalIn: NSRect(
                    x: startX + CGFloat(index) * (diameter + spacing),
                    y: 4,
                    width: diameter,
                    height: diameter
                ))
                signal.color.withAlphaComponent(signal == active ? 1 : 0.16).setFill()
                lamp.fill()
                if signal == active {
                    NSColor.white.withAlphaComponent(0.55).setStroke()
                    lamp.lineWidth = 0.7
                    lamp.stroke()
                }
            }
        }
    }

    private static func lightBulb(active: TrafficSignal) -> NSImage {
        canvas(width: 26) { _ in
            let bulb = NSBezierPath(ovalIn: NSRect(x: 5.5, y: 4, width: 15, height: 13))
            active.color.withAlphaComponent(0.92).setFill()
            bulb.fill()
            NSColor.labelColor.withAlphaComponent(0.9).setStroke()
            bulb.lineWidth = 1.1
            bulb.stroke()

            let base = NSBezierPath(roundedRect: NSRect(x: 9.5, y: 1, width: 7, height: 5), xRadius: 1.5, yRadius: 1.5)
            NSColor.windowBackgroundColor.setFill()
            base.fill()
            NSColor.labelColor.withAlphaComponent(0.9).setStroke()
            base.lineWidth = 1
            base.stroke()

            for angle in stride(from: 0.0, to: 360.0, by: 60.0) {
                let radians = angle * .pi / 180
                let ray = NSBezierPath()
                ray.move(to: NSPoint(x: 13 + cos(radians) * 9.2, y: 10 + sin(radians) * 7.1))
                ray.line(to: NSPoint(x: 13 + cos(radians) * 11.2, y: 10 + sin(radians) * 8.7))
                active.color.setStroke()
                ray.lineWidth = 1.2
                ray.lineCapStyle = .round
                ray.stroke()
            }
        }
    }

    private static func topHatMascot(active: TrafficSignal, frame: Int) -> NSImage {
        canvas(width: 38) { _ in
            let phase = CGFloat(frame % 8) / 8
            let wave = sin(phase * .pi * 2)
            let faceY: CGFloat = active == .red ? abs(wave) * 0.8 : (active == .yellow ? wave * 0.5 : 0)
            let centerX: CGFloat = 18

            let face = NSBezierPath(ovalIn: NSRect(x: 10, y: 2.2 + faceY, width: 16, height: 13.5))
            NSColor(calibratedRed: 1, green: 0.78, blue: 0.25, alpha: 1).setFill()
            face.fill()
            NSColor.labelColor.setStroke()
            face.lineWidth = 1
            face.stroke()

            let brim = NSBezierPath(roundedRect: NSRect(x: 8.4, y: 13.5 + faceY, width: 19.2, height: 2.2), xRadius: 1, yRadius: 1)
            NSColor.labelColor.setFill()
            brim.fill()
            let hat = NSBezierPath(roundedRect: NSRect(x: 12, y: 14.5 + faceY, width: 12, height: 3.4), xRadius: 1.2, yRadius: 1.2)
            NSColor.labelColor.setFill()
            hat.fill()

            NSColor.white.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.3, y: 7.2 + faceY, width: 5.4, height: 4.7)).fill()
            NSBezierPath(ovalIn: NSRect(x: 18.3, y: 7.2 + faceY, width: 5.4, height: 4.7)).fill()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 15, y: 8.1 + faceY, width: 1.8, height: 2.5)).fill()
            NSBezierPath(ovalIn: NSRect(x: 19.1, y: 8.1 + faceY, width: 1.8, height: 2.5)).fill()

            let goggles = NSBezierPath()
            goggles.move(to: NSPoint(x: 11.6, y: 12.2 + faceY))
            goggles.line(to: NSPoint(x: 17.5, y: 12.2 + faceY))
            goggles.line(to: NSPoint(x: 18.5, y: 12.2 + faceY))
            goggles.line(to: NSPoint(x: 24.4, y: 12.2 + faceY))
            active.color.withAlphaComponent(0.88).setStroke()
            goggles.lineWidth = 1.1
            goggles.stroke()

            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: centerX - 2.4, y: 6.9 + faceY))
            beak.line(to: NSPoint(x: centerX, y: 5.2 + faceY))
            beak.line(to: NSPoint(x: centerX + 2.4, y: 6.9 + faceY))
            beak.close()
            NSColor.systemOrange.setFill()
            beak.fill()
            active.color.withAlphaComponent(0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: 10.6, y: 5.5 + faceY, width: 2.4, height: 2.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 23, y: 5.5 + faceY, width: 2.4, height: 2.4)).fill()

            switch active {
            case .red:
                let ballY = 1.2 + abs(wave) * 4.5
                let ball = NSBezierPath(ovalIn: NSRect(x: 29, y: ballY, width: 7, height: 7))
                NSColor.systemOrange.setFill()
                ball.fill()
                NSColor.labelColor.setStroke()
                ball.lineWidth = 0.8
                ball.stroke()
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: 32.5, y: ballY))
                seam.line(to: NSPoint(x: 32.5, y: ballY + 7))
                seam.move(to: NSPoint(x: 29, y: ballY + 3.5))
                seam.line(to: NSPoint(x: 36, y: ballY + 3.5))
                seam.lineWidth = 0.55
                seam.stroke()
            case .yellow:
                let arms = NSBezierPath()
                arms.move(to: NSPoint(x: 10.5, y: 6 + faceY))
                arms.line(to: NSPoint(x: 5.5, y: 9 + wave * 2))
                arms.move(to: NSPoint(x: 25.5, y: 6 + faceY))
                arms.line(to: NSPoint(x: 30.5, y: 9 - wave * 2))
                active.color.setStroke()
                arms.lineWidth = 1.7
                arms.lineCapStyle = .round
                arms.stroke()
            case .green:
                let sparkle = NSBezierPath()
                sparkle.move(to: NSPoint(x: 31, y: 8))
                sparkle.line(to: NSPoint(x: 36, y: 8))
                sparkle.move(to: NSPoint(x: 33.5, y: 5.5))
                sparkle.line(to: NSPoint(x: 33.5, y: 10.5))
                active.color.setStroke()
                sparkle.lineWidth = 1.3
                sparkle.lineCapStyle = .round
                sparkle.stroke()
            }
        }
    }

    private static func basketballMascot(active: TrafficSignal, frame: Int) -> NSImage {
        guard let mascot = basketballMascotImage else {
            return topHatMascot(active: active, frame: frame)
        }
        return canvas(width: 34) { _ in
            let phase = CGFloat(frame % 12) / 12
            let wave = sin(phase * .pi * 2)
            let mascotOffset: NSPoint
            switch active {
            case .red:
                mascotOffset = NSPoint(x: 0, y: abs(wave) * 0.65)
            case .yellow:
                mascotOffset = NSPoint(x: wave * 0.5, y: abs(wave) * 0.25)
            case .green:
                mascotOffset = .zero
            }

            // Draw the supplied character PNG directly. The crop keeps the
            // original face, hair, clothes and basketball pixels unchanged.
            let target = NSRect(
                x: 1.5 + mascotOffset.x,
                y: 0.5 + mascotOffset.y,
                width: 15,
                height: 17
            )
            mascot.draw(
                in: target,
                from: basketballMascotSourceRect,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )

            let badgeCenter = NSPoint(x: 26, y: 8.8)
            let badge = NSBezierPath(ovalIn: NSRect(x: 19, y: 1.8, width: 14, height: 14))
            NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
            badge.fill()
            active.color.withAlphaComponent(0.95).setStroke()
            badge.lineWidth = 1.3
            badge.stroke()

            switch active {
            case .red:
                drawBouncingBall(center: badgeCenter, wave: wave)
            case .yellow:
                drawMusicNotes(center: badgeCenter, wave: wave)
            case .green:
                drawCompletionCheck(center: badgeCenter)
            }
        }
    }

    private static let basketballMascotImage: NSImage? = {
        let resourceURL = Bundle.main.url(forResource: "BasketballMascot", withExtension: "png")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/BasketballMascot.png")
        return NSImage(contentsOf: resourceURL)
    }()

    // The original 1088 × 960 PNG has transparent bounds x=343...744,
    // y=8...735 in AppKit coordinates. This tighter crop keeps the face,
    // bow tie and basketball readable at menu-bar size.
    private static let basketballMascotSourceRect = NSRect(
        x: 335,
        y: 260,
        width: 418,
        height: 475
    )

    private static func drawBouncingBall(center: NSPoint, wave: CGFloat) {
        let ballY = center.y - 3 + abs(wave) * 1.2
        let ballRect = NSRect(x: center.x - 3, y: ballY, width: 6, height: 6)
        let ball = NSBezierPath(ovalIn: ballRect)
        NSColor.systemOrange.setFill()
        ball.fill()
        NSColor.labelColor.withAlphaComponent(0.9).setStroke()
        ball.lineWidth = 0.65
        ball.stroke()

        let seams = NSBezierPath()
        seams.move(to: NSPoint(x: center.x, y: ballRect.minY))
        seams.line(to: NSPoint(x: center.x, y: ballRect.maxY))
        seams.move(to: NSPoint(x: ballRect.minX, y: ballRect.midY))
        seams.line(to: NSPoint(x: ballRect.maxX, y: ballRect.midY))
        seams.lineWidth = 0.5
        seams.stroke()
    }

    private static func drawMusicNotes(center: NSPoint, wave: CGFloat) {
        let notes = NSBezierPath()
        notes.move(to: NSPoint(x: center.x - 3.2, y: center.y + 2.8))
        notes.line(to: NSPoint(x: center.x + 2.2, y: center.y + 4 + wave * 0.7))
        notes.line(to: NSPoint(x: center.x + 2.2, y: center.y - 1))
        notes.move(to: NSPoint(x: center.x - 3.2, y: center.y + 2.8))
        notes.line(to: NSPoint(x: center.x - 3.2, y: center.y - 2.2))
        TrafficSignal.yellow.color.setStroke()
        notes.lineWidth = 1.2
        notes.lineCapStyle = .round
        notes.lineJoinStyle = .round
        notes.stroke()
        TrafficSignal.yellow.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 5.2, y: center.y - 3.5, width: 3.1, height: 2.5)).fill()
        NSBezierPath(ovalIn: NSRect(x: center.x + 0.2, y: center.y - 2.2, width: 3.1, height: 2.5)).fill()
    }

    private static func drawCompletionCheck(center: NSPoint) {
        let check = NSBezierPath()
        check.move(to: NSPoint(x: center.x - 4, y: center.y))
        check.line(to: NSPoint(x: center.x - 1, y: center.y - 3))
        check.line(to: NSPoint(x: center.x + 4.5, y: center.y + 3.5))
        TrafficSignal.green.color.setStroke()
        check.lineWidth = 2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
    }

    private static func statusRing(active: TrafficSignal) -> NSImage {
        canvas(width: 24) { _ in
            let center = NSPoint(x: 12, y: 9)
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: 7, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.16).setStroke()
            track.lineWidth = 3
            track.stroke()

            let progress = NSBezierPath()
            progress.appendArc(withCenter: center, radius: 7, startAngle: 90, endAngle: 405, clockwise: false)
            active.color.setStroke()
            progress.lineWidth = 3
            progress.lineCapStyle = .round
            progress.stroke()

            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 10, y: 7, width: 4, height: 4)).fill()
        }
    }
}
