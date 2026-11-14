import AppKit

/// Menu bar icon: an hourglass whose sand level shows how much time the next
/// app has left before it is quit. The upper bulb drains from the sand surface
/// down to the neck, while the sand piles up in the lower bulb, so 1 hour is
/// full, 30 minutes is half, and 0 leaves the upper bulb empty.
@MainActor
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)
    static let steps = 16

    private static var cache: [String: NSImage] = [:]

    // Glass geometry (18×18 canvas, origin bottom-left).
    private static let topY: CGFloat = 15.4
    private static let bottomY: CGFloat = 2.6
    private static let waistY: CGFloat = 9.0
    private static let leftX: CGFloat = 4.1
    private static let rightX: CGFloat = 13.9
    private static let waistHalfGap: CGFloat = 0.35

    /// - Parameters:
    ///   - fraction: Remaining time as a fraction of the threshold (0...1),
    ///     or `nil` for a plain hourglass.
    ///   - paused: Draws a "not now" slash when auto-quit is paused.
    static func make(fraction: CGFloat?, paused: Bool = false) -> NSImage {
        let step = fraction.map { max(0, min(steps, Int(($0 * CGFloat(steps)).rounded()))) } ?? -1
        let key = "\(step)-\(paused)"
        if let cached = cache[key] { return cached }

        let image = NSImage(size: size, flipped: false) { _ in
            let glass = glassPath
            drawSand(glass: glass, fraction: step < 0 ? nil : CGFloat(step) / CGFloat(steps))
            NSColor.black.setStroke()
            glass.stroke()
            if paused {
                drawPauseSlash()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "SwiftQuit, paused" : "SwiftQuit"

        cache[key] = image
        return image
    }

    // MARK: - Glass

    /// Classic hourglass silhouette: flat top and bottom bars with straight,
    /// tapered sides. Sharp corners are deliberately avoided by the round joins
    /// so nothing blobs up at 18 pt.
    private static var glassPath: NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: NSPoint(x: leftX, y: topY))
        path.line(to: NSPoint(x: rightX, y: topY))
        path.line(to: NSPoint(x: 9.0 + waistHalfGap, y: waistY))
        path.line(to: NSPoint(x: rightX, y: bottomY))
        path.line(to: NSPoint(x: leftX, y: bottomY))
        path.line(to: NSPoint(x: 9.0 - waistHalfGap, y: waistY))
        path.close()
        return path
    }

    // MARK: - Sand

    private static func drawSand(glass: NSBezierPath, fraction: CGFloat?) {
        guard let fraction else { return }
        let remaining = max(0, min(1, fraction))
        let elapsed = 1 - remaining

        NSGraphicsContext.current?.saveGraphicsState()
        glass.addClip()

        NSColor.black.withAlphaComponent(0.8).setFill()

        // Upper bulb: the sand surface descends towards the neck.
        if remaining > 0 {
            let level = waistY + remaining * (topY - waistY)
            NSRect(x: 0, y: waistY, width: size.width, height: level - waistY).fill()
        }

        // Lower bulb: sand gathers in a mound that flattens as the bulb fills.
        if elapsed > 0 {
            let level = bottomY + elapsed * (waistY - bottomY)
            let peak = 1.1 * (1 - elapsed) * min(1, elapsed * 5)
            let mound = NSBezierPath()
            mound.move(to: NSPoint(x: 3.4, y: bottomY))
            mound.line(to: NSPoint(x: 3.4, y: level))
            mound.curve(
                to: NSPoint(x: 14.6, y: level),
                controlPoint1: NSPoint(x: 6.2, y: level + peak * 1.7),
                controlPoint2: NSPoint(x: 11.8, y: level + peak * 1.7)
            )
            mound.line(to: NSPoint(x: 14.6, y: bottomY))
            mound.close()
            mound.fill()
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Pause

    /// A diagonal "not now" stroke with a small gap around it, so it stays legible
    /// over the hourglass at 18 pt.
    private static func drawPauseSlash() {
        guard let context = NSGraphicsContext.current else { return }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3.4, y: 3.4))
        path.line(to: NSPoint(x: 14.6, y: 14.6))
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        context.saveGraphicsState()
        context.compositingOperation = .destinationOut
        path.lineWidth = 4.4
        path.stroke()
        context.restoreGraphicsState()

        NSColor.black.setStroke()
        path.lineWidth = 1.6
        path.stroke()
    }
}
