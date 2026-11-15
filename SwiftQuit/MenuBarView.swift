import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @State private var isQuitAppHovered = false

    private var strings: Strings { state.strings }

    private var idleLabel: String {
        strings.duration(minutes: Int(state.idleMinutes))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if state.isPaused {
                pauseBanner
                Divider()
            }
            if !state.pendingQuits.isEmpty {
                pendingQuitPanel
                Divider()
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(state.displayedApps) { app in
                        AppRow(app: app)
                    }
                    if state.runningBackgroundCount > 0 {
                        backgroundSection
                    } else if !state.backgroundBlacklist.isEmpty {
                        dormantBackgroundSection
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
        HStack(spacing: 10) {
            Text("SwiftQuit")
                .font(.system(size: 17, weight: .semibold))

            Toggle(strings.autoQuit, isOn: $state.isAutoQuitEnabled)
                .controlSize(.small)
                .font(.system(size: 12))

            Spacer()

            Menu {
                Button(strings.duration(minutes: 15)) { state.idleMinutes = 15 }
                Button(strings.duration(minutes: 30)) { state.idleMinutes = 30 }
                Button(strings.duration(minutes: 60)) { state.idleMinutes = 60 }
                Button(strings.duration(minutes: 120)) { state.idleMinutes = 120 }
                Button(strings.duration(minutes: 240)) { state.idleMinutes = 240 }
                Button(strings.duration(minutes: 480)) { state.idleMinutes = 480 }
                Button(strings.duration(minutes: 1440)) { state.idleMinutes = 1440 }
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 4)

            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(strings.backgroundSection)
                    .font(.system(size: 12, weight: .medium))
                Text(strings.backgroundSummary(
                    blacklisted: state.blacklistedBackgroundItems.count,
                    kept: state.keptBackgroundItems.count
                ))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                Spacer()
                Button(strings.manageEllipsis) {
                    state.openSettings(.background)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14)

            // Only the blacklisted items are listed here; the full list with the
            // whitelist lives in Settings so the popover stays short. Menu bar
            // apps and command line processes are separated by a small caption
            // when both are present.
            let blacklisted = state.blacklistedBackgroundItems
            let menuBarItems = blacklisted.filter { if case .app = $0 { return true }; return false }
            let processItems = blacklisted.filter { if case .process = $0 { return true }; return false }

            if blacklisted.isEmpty {
                Text(strings.backgroundPopoverEmpty)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.leading, 20)
            } else if processItems.isEmpty {
                ForEach(menuBarItems) { item in
                    BackgroundRow(item: item)
                }
            } else if menuBarItems.isEmpty {
                ForEach(processItems) { item in
                    BackgroundRow(item: item)
                }
            } else {
                popoverGroupLabel(strings.backgroundMenuBarSection)
                ForEach(menuBarItems) { item in
                    BackgroundRow(item: item)
                }
                popoverGroupLabel(strings.backgroundProcessSection)
                ForEach(processItems) { item in
                    BackgroundRow(item: item)
                }
            }

            BackgroundSweepButton(
                title: strings.closeBackgroundApps,
                count: state.blacklistedBackgroundItems.count,
                isBusy: state.isBackgroundSweepInFlight,
                isEnabled: !state.blacklistedBackgroundItems.isEmpty && !state.isBackgroundSweepInFlight,
                action: { state.closeBlacklistedBackgroundApps() }
            )
            .help(strings.closeBackgroundAppsHint)
            .padding(.horizontal, 14)
            .padding(.top, 2)

            if let result = state.lastBackgroundCleanup {
                HStack(spacing: 6) {
                    Text(strings.backgroundSweepResult(quit: result.quitCount, kept: result.keptCount))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if result.skippedActiveCount > 0 {
                        Text(strings.backgroundSweepSkipped(result.skippedActiveCount))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if result.stubbornCount > 0 {
                        Text(strings.backgroundSweepWarning(stubborn: result.stubbornCount))
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 4)
    }

    private func popoverGroupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.leading, 20)
            .padding(.top, 2)
    }

    /// Shown when every blacklisted app is currently closed, so the list does
    /// not silently disappear from the popover.
    private var dormantBackgroundSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.vertical, 4)
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(strings.backgroundSection)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(strings.manageEllipsis) {
                    state.openSettings(.background)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14)

            Text(strings.backgroundAllClosed(count: state.backgroundBlacklist.count))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.leading, 20)
        }
        .padding(.bottom, 4)
    }

    /// Apps that are in their pre-quit grace period. Shown inline so the user
    /// sees what is about to be quit even when notification permission was
    /// denied and no banner appears.
    private var pendingQuitPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text(strings.pendingQuitSection)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.orange)
                Spacer()
                Button(strings.keepAllRunning) {
                    state.keepAllPending()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 14)

            ForEach(pendingApps) { app in
                HStack(spacing: 8) {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(app.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Spacer()
                    if let seconds = state.remainingSeconds[app.bundleID] {
                        Text(strings.quittingIn(seconds: max(1, Int(seconds.rounded(.up)))))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                    Button(strings.keepRunning) {
                        state.keepRunning(bundleID: app.bundleID)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 14)
                .padding(.leading, 6)
            }
        }
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.07))
    }

    private var pendingApps: [AppInfo] {
        state.runningApps.filter { state.pendingQuits.contains($0.bundleID) }
    }

    private var pauseBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.orange)
            Text(strings.pauseBanner(remaining: strings.pauseRemaining(seconds: state.pauseRemaining)))
                .font(.system(size: 12))
            Spacer()
            Button(strings.resumeNow) {
                state.resumePause()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.08))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Toggle(strings.launchAtLogin, isOn: $state.launchAtLogin)
                    .controlSize(.small)
                    .font(.system(size: 13))
                Spacer()
                Button(strings.settings) {
                    state.openSettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                Button(strings.quitApp) {
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
            if state.launchAtLoginFailed {
                Text(strings.loginItemError)
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

    private var strings: Strings { state.strings }

    private var isExcluded: Bool {
        state.excludedBundleIDs.contains(app.bundleID)
    }

    private var isForeground: Bool {
        state.foregroundBundleID == app.bundleID
    }

    private var isFinder: Bool {
        app.bundleID == SystemApps.finderBundleID
    }

    private var isQuitting: Bool {
        state.pendingQuits.contains(app.bundleID)
    }

    private var isUnresponsive: Bool {
        state.unresponsiveApps.contains(app.bundleID)
    }

    private var showsForceQuit: Bool {
        isUnresponsive && !isFinder
    }

    private var remainingText: String? {
        if isUnresponsive {
            return strings.notResponding
        }
        guard state.isAutoQuitEnabled else { return nil }
        if isExcluded { return nil }
        if isForeground { return nil }
        guard let sec = state.remainingSeconds[app.bundleID] else { return nil }
        if isQuitting {
            return strings.quittingIn(seconds: max(1, Int(sec.rounded(.up))))
        }
        if sec <= 0 { return strings.quitting }
        return strings.countdown(minutes: Int(sec) / 60, seconds: Int(sec) % 60)
    }

    var body: some View {
        HStack(spacing: 8) {
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
            .help(strings.includeInAutoQuitHint)

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
                    .foregroundColor(isUnresponsive ? .orange : (isQuitting || (state.remainingSeconds[app.bundleID] ?? 1) <= 0 ? .red : .orange))
            }
            Spacer()
            Button(showsForceQuit ? strings.forceQuit : (isFinder ? strings.closeWindows : strings.quit)) {
                if showsForceQuit {
                    state.forceQuitNow(app)
                } else {
                    state.quitNow(app)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(isQuitHovered ? .red : (showsForceQuit ? .orange : .secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isQuitHovered ? Color.red.opacity(0.1) : Color.clear)
            )
            .overlay(HoverObserver(isHovered: $isQuitHovered).allowsHitTesting(false))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 54, alignment: .trailing)
            .help(showsForceQuit ? strings.forceQuitHint : (isFinder ? strings.closeWindowsHint : strings.quitHint))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(isForeground ? Color.accentColor.opacity(0.08) : Color.clear)
        .contextMenu {
            if !isFinder {
                Button(strings.quit) { state.quitNow(app) }
                Button(strings.forceQuit) { state.forceQuitNow(app) }
            } else {
                Button(strings.closeWindows) { state.quitNow(app) }
            }
            Divider()
            Button(isExcluded ? strings.includeInAutoQuit : strings.excludeFromAutoQuit) {
                if isExcluded {
                    state.excludedBundleIDs.remove(app.bundleID)
                } else {
                    state.excludedBundleIDs.insert(app.bundleID)
                }
            }
        }
        .onDisappear {
            isQuitHovered = false
        }
    }
}

/// Primary action of the background section. Drawn with a ZStack so the tinted
/// background cannot inherit the label's foreground style (which would paint
/// the pill solid and swallow the text).
struct BackgroundSweepButton: View {
    let title: String
    let count: Int
    let isBusy: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var isEmphasized: Bool { isHovered && isEnabled }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.orange.opacity(isEmphasized ? 1 : 0.14))
                HStack(spacing: 6) {
                    if isBusy {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(isEmphasized ? Color.white.opacity(0.9) : Color.orange)
                    }
                }
                .foregroundColor(isEmphasized ? Color.white : Color.orange)
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

/// One background item row in the popover: blacklisted items only, with a way to
/// take the item back off the list without opening Settings.
struct BackgroundRow: View {
    let item: BackgroundItem
    @EnvironmentObject var state: AppState
    @State private var isHovered = false

    private var strings: Strings { state.strings }

    var body: some View {
        HStack(spacing: 8) {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 18, height: 18)
            }
            Text(item.name)
                .lineLimit(1)
                .font(.system(size: 13))
            if let detail = item.processCountLabel {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if item.isActive {
                Text(strings.backgroundActive)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.orange.opacity(0.14))
                    )
            }
            Spacer()
            Button(strings.removeFromList) {
                state.setBackgroundBlacklisted(false, target: item.target)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(isHovered ? .orange : .secondary)
            .help(strings.removeFromListHint)
        }
        .padding(.horizontal, 14)
        .padding(.leading, 20)
        .padding(.vertical, 3)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
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
