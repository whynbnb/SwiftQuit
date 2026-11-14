import AppKit

/// Custom template image for the menu bar: an hourglass, representing apps
/// that have been idle for too long. A slashed variant indicates a pause.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make(paused: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            let glass = NSBezierPath()
            glass.lineWidth = 1.75
            glass.lineCapStyle = .round
            glass.lineJoinStyle = .round

            glass.move(to: NSPoint(x: 3.9, y: 15.6))
            glass.line(to: NSPoint(x: 14.1, y: 15.6))
            glass.curve(
                to: NSPoint(x: 9.3, y: 9.0),
                controlPoint1: NSPoint(x: 12.2, y: 13.6),
                controlPoint2: NSPoint(x: 10.4, y: 10.5)
            )
            glass.curve(
                to: NSPoint(x: 14.1, y: 2.4),
                controlPoint1: NSPoint(x: 10.4, y: 7.5),
                controlPoint2: NSPoint(x: 12.2, y: 4.4)
            )
            glass.line(to: NSPoint(x: 3.9, y: 2.4))
            glass.curve(
                to: NSPoint(x: 8.7, y: 9.0),
                controlPoint1: NSPoint(x: 6.4, y: 4.4),
                controlPoint2: NSPoint(x: 7.6, y: 7.5)
            )
            glass.curve(
                to: NSPoint(x: 3.9, y: 15.6),
                controlPoint1: NSPoint(x: 7.6, y: 10.5),
                controlPoint2: NSPoint(x: 6.4, y: 13.6)
            )
            glass.close()
            NSColor.black.setStroke()
            glass.stroke()

            if paused {
                drawPauseSlash()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "SwiftQuit, paused" : "SwiftQuit"
        return image
    }

    /// A diagonal "not now" stroke with a small gap around it, so it stays legible
    /// over the hourglass at 18 pt.
    private static func drawPauseSlash() {
        guard let context = NSGraphicsContext.current else { return }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: 3.4, y: 3.4))
        path.line(to: NSPoint(x: 14.6, y: 14.6))
        path.lineWidth = 1.6
        path.lineCapStyle = .round

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
