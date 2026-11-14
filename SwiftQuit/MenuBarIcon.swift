import AppKit

/// Custom template image for the menu bar: an hourglass, representing apps
/// that have been idle for too long.
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
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

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SwiftQuit"
        return image
    }
}
