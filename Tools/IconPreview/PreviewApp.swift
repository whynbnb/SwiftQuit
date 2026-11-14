import SwiftUI
import Combine

@main
struct IconPreviewApp: App {
    var body: some Scene {
        WindowGroup("SwiftQuit 沙漏图标预览") {
            PreviewView()
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
struct PreviewView: View {
    private let steps = MenuBarIcon.steps

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                menuBarSection
                drainSection
                keyStatesSection
                allStatesSection
                footer
            }
            .padding(24)
        }
        .frame(width: 860, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SwiftQuit 菜单栏沙漏图标")
                .font(.system(size: 22, weight: .semibold))
            Text("沙量 = 最近一个待退出 App 的剩余时间 ÷ 该 App 的空闲阈值。默认阈值 60 分钟时：1 小时全满、30 分钟上下各一半、0 为空。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("菜单栏真实尺寸（18 pt）")
            VStack(spacing: 12) {
                menuBarStrip(dark: false)
                menuBarStrip(dark: true)
            }
        }
    }

    private func menuBarStrip(dark: Bool) -> some View {
        let tint: Color = dark ? .white : .black
        return HStack(spacing: 22) {
            ForEach([steps, steps * 3 / 4, steps / 2, steps / 4, 0], id: \.self) { step in
                icon(step: step, size: 18, tint: tint)
            }
            icon(step: nil, size: 18, tint: tint)
            icon(step: steps / 2, size: 18, paused: true, tint: tint)
            Spacer()
            Text(dark ? "深色菜单栏" : "浅色菜单栏")
                .font(.system(size: 11))
                .foregroundStyle(dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(dark ? Color.black : Color.white))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
        )
    }

    private var drainSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("动态演示（15 秒走完一轮，循环）")
            DrainDemo()
        }
    }

    private var keyStatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("关键状态（56 pt）")
            HStack(alignment: .top, spacing: 28) {
                bigState(step: steps, caption: "60 分钟 · 全满")
                bigState(step: steps * 3 / 4, caption: "45 分钟")
                bigState(step: steps / 2, caption: "30 分钟 · 各半")
                bigState(step: steps / 4, caption: "15 分钟")
                bigState(step: 0, caption: "0 · 空")
                bigState(step: nil, caption: "无倒计时")
                bigState(step: steps / 2, paused: true, caption: "暂停")
            }
        }
    }

    private var allStatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("全部 \(steps + 1) 档（32 pt）")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 9),
                spacing: 12
            ) {
                ForEach(Array((0...steps).reversed()), id: \.self) { step in
                    VStack(spacing: 3) {
                        icon(step: step, size: 32)
                        Text(label(for: step))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text("静态对照图：运行 build.sh 生成 build/sheet.png；图标代码来自 SwiftQuit/MenuBarIcon.swift。")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func bigState(step: Int?, paused: Bool = false, caption: String) -> some View {
        VStack(spacing: 8) {
            icon(step: step, size: 56, paused: paused)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func icon(step: Int?, size: CGFloat, paused: Bool = false, tint: Color = .primary) -> some View {
        let fraction = step.map { CGFloat($0) / CGFloat(steps) }
        return Image(nsImage: MenuBarIcon.make(fraction: fraction, paused: paused))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .foregroundStyle(tint)
    }

    private func label(for step: Int) -> String {
        let minutes = Int((Double(step) / Double(steps) * 60).rounded())
        return "\(minutes)m"
    }
}

/// Cycles the hourglass from full to empty in 15 seconds so the draining can be
/// seen without waiting for a real countdown.
@MainActor
private struct DrainDemo: View {
    @State private var fraction: CGFloat = 1

    private let duration: Double = 15
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 26) {
            HStack(spacing: 20) {
                Image(nsImage: MenuBarIcon.make(fraction: fraction))
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                Image(nsImage: MenuBarIcon.make(fraction: fraction))
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }
            .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Text("剩余 \(Int((fraction * 60).rounded())) 分钟")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(fraction))
                    .frame(width: 220)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .onReceive(timer) { _ in
            fraction -= CGFloat(0.05 / duration)
            if fraction <= 0 {
                fraction = 1
            }
        }
    }
}
