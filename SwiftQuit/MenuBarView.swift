import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @State private var isQuitAppHovered = false

    private var idleLabel: String {
        let m = Int(state.idleMinutes)
        if m >= 60 && m % 60 == 0 {
            return "\(m / 60)h"
        }
        return "\(m)min"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.runningApps) { app in
                        AppRow(app: app)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(maxHeight: .infinity)
        .onDisappear {
            isQuitAppHovered = false
        }
    }

    private var header: some View {
        HStack {
            Text("SwiftQuit")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            if state.isAutoQuitEnabled {
                Text("Auto-quit: \(idleLabel)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Auto Quit", isOn: $state.isAutoQuitEnabled)
                    .controlSize(.small)
                    .font(.system(size: 12))
                Spacer()
                Menu {
                    Button("15 min") { state.idleMinutes = 15 }
                    Button("30 min") { state.idleMinutes = 30 }
                    Button("1 hour") { state.idleMinutes = 60 }
                    Button("2 hours") { state.idleMinutes = 120 }
                    Button("4 hours") { state.idleMinutes = 240 }
                    Button("8 hours") { state.idleMinutes = 480 }
                    Button("24 hours") { state.idleMinutes = 1440 }
                } label: {
                    Text(idleLabel)
                        .font(.system(size: 13))
                }
                .controlSize(.small)
                .frame(width: 72)
                .disabled(!state.isAutoQuitEnabled)
                Stepper("", value: $state.idleMinutes, in: 5...1440, step: 5)
                    .controlSize(.small)
                    .disabled(!state.isAutoQuitEnabled)
            }
            HStack {
                Toggle("Launch at Login", isOn: $state.launchAtLogin)
                    .controlSize(.small)
                    .font(.system(size: 13))
                Spacer()
                Button("Quit SwiftQuit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(isQuitAppHovered ? .red : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isQuitAppHovered ? Color.red.opacity(0.1) : Color.clear)
                )
                .overlay(HoverObserver(isHovered: $isQuitAppHovered).allowsHitTesting(false))
            }
            if let error = state.launchAtLoginError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct AppRow: View {
    let app: AppInfo
    @EnvironmentObject var state: AppState
    @State private var isQuitHovered = false

    private var isExcluded: Bool {
        state.excludedBundleIDs.contains(app.bundleID)
    }

    private var isForeground: Bool {
        state.foregroundBundleID == app.bundleID
    }

    private var isQuitting: Bool {
        guard let sec = state.remainingSeconds[app.bundleID] else { return false }
        return sec <= 0
    }

    private var remainingText: String? {
        guard state.isAutoQuitEnabled else { return nil }
        if isExcluded { return nil }
        if isForeground { return nil }
        guard let sec = state.remainingSeconds[app.bundleID] else { return nil }
        if sec <= 0 { return "Quitting…" }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return m > 0 ? "\(m)m\(s)s" : "\(s)s"
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            }
            Text(app.name)
                .lineLimit(1)
                .font(.system(size: 15))
            if isForeground {
                Text("●")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
            if let text = remainingText {
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(isQuitting ? .red : .orange)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { !isExcluded },
                set: { checked in
                    if checked {
                        state.excludedBundleIDs.remove(app.bundleID)
                    } else {
                        state.excludedBundleIDs.insert(app.bundleID)
                    }
                }
            ))
            .controlSize(.small)
            .help("Include in auto-quit")
            Button("Quit") {
                state.quitNow(app)
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(isQuitHovered ? .red : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isQuitHovered ? Color.red.opacity(0.1) : Color.clear)
            )
            .overlay(HoverObserver(isHovered: $isQuitHovered).allowsHitTesting(false))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(isForeground ? Color.accentColor.opacity(0.08) : Color.clear)
        .onDisappear {
            isQuitHovered = false
        }
    }
}

struct HoverObserver: NSViewRepresentable {
    @Binding var isHovered: Bool

    func makeNSView(context: Context) -> HoverNSView {
        let view = HoverNSView()
        view.onHover = { hovering in
            DispatchQueue.main.async {
                self.isHovered = hovering
            }
        }
        return view
    }

    func updateNSView(_ nsView: HoverNSView, context: Context) {}

    final class HoverNSView: NSView {
        var onHover: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area = trackingArea {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHover?(true)
        }

        override func mouseExited(with event: NSEvent) {
            onHover?(false)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                onHover?(false)
            }
        }
    }
}
