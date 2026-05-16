import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

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
    }

    private var header: some View {
        HStack {
            Text("SwiftQuit")
                .font(.headline)
            Spacer()
            if state.isAutoQuitEnabled {
                Text("Auto-quit: \(idleLabel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack {
                Toggle("Auto Quit", isOn: $state.isAutoQuitEnabled)
                    .controlSize(.small)
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
                        .font(.system(size: 11))
                }
                .controlSize(.small)
                .frame(width: 70)
                .disabled(!state.isAutoQuitEnabled)
                Stepper("", value: $state.idleMinutes, in: 5...1440, step: 5)
                    .controlSize(.small)
                    .disabled(!state.isAutoQuitEnabled)
            }
            HStack {
                Toggle("Launch at Login", isOn: $state.launchAtLogin)
                    .controlSize(.small)
                Spacer()
                Button("Quit SwiftQuit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct AppRow: View {
    let app: AppInfo
    @EnvironmentObject var state: AppState

    private var isExcluded: Bool {
        state.excludedBundleIDs.contains(app.bundleID)
    }

    private var isForeground: Bool {
        state.foregroundBundleID == app.bundleID
    }

    private var remainingText: String? {
        guard state.isAutoQuitEnabled else { return nil }
        if isExcluded { return nil }
        if isForeground { return nil }
        guard let sec = state.remainingSeconds[app.bundleID] else { return nil }
        if sec <= 0 { return nil }
        let m = Int(sec) / 60
        let s = Int(sec) % 60
        return m > 0 ? "\(m)m\(s)s" : "\(s)s"
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
                .lineLimit(1)
                .font(.system(size: 12))
            if isForeground {
                Text("●")
                    .font(.system(size: 8))
                    .foregroundColor(.green)
            }
            if let text = remainingText {
                Text(text)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange)
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
            .controlSize(.mini)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(isForeground ? Color.accentColor.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
    }
}
