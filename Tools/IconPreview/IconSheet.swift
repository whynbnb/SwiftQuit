import AppKit

/// Renders a contact sheet with every hourglass state so the icon can be
/// reviewed (and regenerated) without waiting for a real countdown.
@main
@MainActor
struct IconSheet {
    @MainActor
    static func main() {
        let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sheet.png"

        let width: CGFloat = 1000
        let height: CGFloat = 680
        let scale: CGFloat = 2

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width * scale),
            pixelsHigh: Int(height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let context = NSGraphicsContext.current?.cgContext else { exit(1) }
        context.scaleBy(x: scale, y: scale)

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        drawHeader(width: width, height: height)

        var top: CGFloat = 92
        drawSection("菜单栏真实尺寸（18 pt）", top: top, height: height)
        top += 22
        drawMenuBarStrip(
            top: top, height: height, width: width,
            fill: .white, border: NSColor.black.withAlphaComponent(0.18), tint: .black,
            caption: "浅色菜单栏"
        )
        top += 56
        drawMenuBarStrip(
            top: top, height: height, width: width,
            fill: .black, border: NSColor.black.withAlphaComponent(0.8), tint: .white,
            caption: "深色菜单栏"
        )

        top += 82
        drawSection("关键状态（56 pt）", top: top, height: height)
        drawKeyStates(top: top + 22, height: height)

        top += 156
        drawSection("全部 17 档（32 pt，按 60 分钟阈值）", top: top, height: height)
        drawAllStates(top: top + 20, height: height)

        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: output))
        print("Wrote \(output)")
    }

    // MARK: - Sections

    private static func drawHeader(width: CGFloat, height: CGFloat) {
        drawText(
            "SwiftQuit 菜单栏沙漏图标",
            x: 40, top: 24, width: width - 80, height: height,
            size: 24, weight: .semibold
        )
        drawText(
            "沙量 = 最近一个待退出 App 的剩余时间 ÷ 该 App 的空闲阈值。默认阈值 60 分钟时：1 小时全满、30 分钟上下各半、0 为空。",
            x: 40, top: 58, width: width - 80, height: height,
            size: 12, color: .darkGray
        )
    }

    private static func drawSection(_ text: String, top: CGFloat, height: CGFloat) {
        drawText(text, x: 40, top: top, width: 600, height: height, size: 13, weight: .medium, color: .darkGray)
    }

    private static func drawMenuBarStrip(
        top: CGFloat, height: CGFloat, width: CGFloat,
        fill: NSColor, border: NSColor, tint: NSColor, caption: String
    ) {
        let rect = NSRect(x: 40, y: height - top - 46, width: width - 80, height: 46)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        fill.setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = 1
        path.stroke()

        let states: [(CGFloat?, Bool)] = [
            (1.0, false), (0.75, false), (0.5, false), (0.25, false), (0.0, false),
            (nil, false), (0.5, true),
        ]
        var x = rect.minX + 24
        for (fraction, paused) in states {
            drawIcon(fraction: fraction, paused: paused, size: 18, x: x, top: top + 14, height: height, tint: tint)
            x += 40
        }

        let captionSize: CGFloat = 11
        let captionWidth = caption.size(withAttributes: [.font: NSFont.systemFont(ofSize: captionSize)]).width
        drawText(
            caption,
            x: rect.maxX - captionWidth - 18,
            top: top + 17,
            width: captionWidth + 4,
            height: height,
            size: captionSize,
            color: tint == .black ? NSColor.black.withAlphaComponent(0.45) : NSColor.white.withAlphaComponent(0.5)
        )
    }

    private static func drawKeyStates(top: CGFloat, height: CGFloat) {
        let states: [(CGFloat?, Bool, String)] = [
            (1.0, false, "60 分钟 · 全满"),
            (0.75, false, "45 分钟"),
            (0.5, false, "30 分钟 · 各半"),
            (0.25, false, "15 分钟"),
            (0.0, false, "0 · 空"),
            (nil, false, "无倒计时"),
            (0.5, true, "暂停"),
        ]
        var x: CGFloat = 48
        for (fraction, paused, caption) in states {
            drawIcon(fraction: fraction, paused: paused, size: 56, x: x, top: top, height: height, tint: .black)
            drawText(
                caption,
                x: x - 12,
                top: top + 66,
                width: 80,
                height: height,
                size: 10,
                color: .darkGray,
                centered: true
            )
            x += 130
        }
    }

    private static func drawAllStates(top: CGFloat, height: CGFloat) {
        let columns = 9
        let cellWidth: CGFloat = 100
        for step in stride(from: MenuBarIcon.steps, through: 0, by: -1) {
            let index = MenuBarIcon.steps - step
            let column = index % columns
            let row = index / columns
            let x = 44 + CGFloat(column) * cellWidth
            let y = top + CGFloat(row) * 76
            drawIcon(
                fraction: CGFloat(step) / CGFloat(MenuBarIcon.steps),
                paused: false,
                size: 32,
                x: x + cellWidth / 2 - 16,
                top: y,
                height: height,
                tint: .black
            )
            let minutes = Int((Double(step) / Double(MenuBarIcon.steps) * 60).rounded())
            drawText(
                "\(minutes)m",
                x: x,
                top: y + 38,
                width: cellWidth,
                height: height,
                size: 9,
                color: .gray,
                centered: true
            )
        }
    }

    // MARK: - Drawing helpers

    private static func drawIcon(
        fraction: CGFloat?, paused: Bool, size: CGFloat,
        x: CGFloat, top: CGFloat, height: CGFloat, tint: NSColor
    ) {
        let image = MenuBarIcon.make(fraction: fraction, paused: paused)
        let tinted = tinted(image, color: tint, size: size)
        tinted.draw(in: NSRect(x: x, y: height - top - size, width: size, height: size))
    }

    private static func tinted(_ image: NSImage, color: NSColor, size: CGFloat) -> NSImage {
        let result = NSImage(size: NSSize(width: size, height: size))
        result.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        color.set()
        NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    private static func drawText(
        _ text: String,
        x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .black,
        centered: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = centered ? .center : .left
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let rect = NSRect(x: x, y: height - top - size * 1.6, width: width, height: size * 1.8)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
