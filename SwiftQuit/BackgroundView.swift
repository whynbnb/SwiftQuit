import SwiftUI

/// Settings tab for background work. Covers both menu bar agents and command
/// line processes/daemons, none of which follow the idle countdown. The user
/// blacklists some of them and stops the whole batch with one button.
struct BackgroundSettingsView: View {
    @EnvironmentObject private var state: AppState

    private var strings: Strings { state.strings }

    private var blacklistedCount: Int { state.blacklistedBackgroundItems.count }
    private var keptCount: Int { state.keptBackgroundItems.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(strings.backgroundSummary(blacklisted: blacklistedCount, kept: keptCount))
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                Button {
                    state.closeBlacklistedBackgroundApps()
                } label: {
                    Text(strings.closeNow)
                }
                .controlSize(.small)
                .disabled(blacklistedCount == 0 || state.isBackgroundSweepInFlight)
                .help(strings.closeBackgroundAppsHint)
            }

            Text(strings.backgroundDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(strings.skipActiveBackgroundItems, isOn: $state.skipActiveBackgroundItems)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help(strings.skipActiveBackgroundItemsHint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var list: some View {
        let items = state.backgroundItems
        let dormant = state.dormantBlacklistedEntries
        if items.isEmpty && dormant.isEmpty {
            Spacer()
            Text(strings.backgroundEmpty)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        } else {
            // Menu bar apps and command line processes are different things:
            // one is a GUI app that can be asked to quit, the other is a bare
            // process that has to be signalled. They never share a section.
            let menuBarItems = items.compactMap { item -> BackgroundItem? in
                if case .app = item { return item }
                return nil
            }
            let processItems = items.compactMap { item -> BackgroundItem? in
                if case .process = item { return item }
                return nil
            }
            let dormantApps = dormant.filter { entry in
                if case .app = entry.target { return true }
                return false
            }
            let dormantProcesses = dormant.filter { entry in
                if case .process = entry.target { return true }
                return false
            }

            List {
                if !menuBarItems.isEmpty || !dormantApps.isEmpty {
                    Section {
                        ForEach(menuBarItems) { item in
                            runningRow(for: item)
                        }
                        ForEach(dormantApps) { entry in
                            dormantRow(for: entry)
                        }
                    } header: {
                        Text(strings.backgroundMenuBarSection)
                    }
                }

                if !processItems.isEmpty || !dormantProcesses.isEmpty {
                    Section {
                        ForEach(processItems) { item in
                            runningRow(for: item)
                        }
                        ForEach(dormantProcesses) { entry in
                            dormantRow(for: entry)
                        }
                    } header: {
                        Text(strings.backgroundProcessSection)
                    }
                }

                // Normally listed and stoppable, but hidden while SwiftQuit is
                // running inside them: stopping an ancestor would kill the
                // terminal session that launched the app.
                if !state.ancestorProcesses.isEmpty {
                    Section {
                        ForEach(state.ancestorProcesses) { group in
                            BackgroundToggleRow(
                                target: .process(path: group.id),
                                name: group.name,
                                icon: nil,
                                detail: group.displayPath,
                                strings: strings,
                                isExcluded: true
                            )
                        }
                    } header: {
                        Text(strings.backgroundAncestorSection)
                    } footer: {
                        Text(strings.backgroundAncestorNote)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func runningRow(for item: BackgroundItem) -> some View {
        BackgroundToggleRow(
            target: item.target,
            name: item.name,
            icon: item.icon,
            detail: item.detail,
            strings: strings,
            activity: activity(for: item)
        )
    }

    /// A short "active / idle" label for CLI processes. Menu bar apps have no
    /// CPU measurement, so they show nothing.
    private func activity(for item: BackgroundItem) -> BackgroundActivity? {
        guard item.hasActivitySample else { return nil }
        if item.isActive {
            return .active(cpu: item.cpuPercent ?? 0)
        }
        return .idle
    }

    /// A blacklisted item that is not running now. It stays on the list so it is
    /// stopped again the next time it appears; the switch takes it off.
    private func dormantRow(for entry: BackgroundEntry) -> some View {
        BackgroundToggleRow(
            target: entry.target,
            name: entry.name,
            icon: nil,
            detail: detail(for: entry),
            strings: strings,
            isDormant: true
        )
    }

    private func detail(for entry: BackgroundEntry) -> String? {
        switch entry.target {
        case .app: return nil
        case .process(let path):
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let result = state.lastBackgroundCleanup {
                Text(strings.backgroundSweepResult(quit: result.quitCount, kept: result.keptCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if result.skippedActiveCount > 0 {
                    Text(strings.backgroundSweepSkipped(result.skippedActiveCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if result.stubbornCount > 0 {
                    Text(strings.backgroundSweepWarning(stubborn: result.stubbornCount))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(strings.backgroundIntro)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// How busy a background process is, as shown next to its name.
enum BackgroundActivity {
    case active(cpu: Double)
    case idle
}

/// One row of the background tab: the switch means "stop this during a sweep".
struct BackgroundToggleRow: View {
    @EnvironmentObject private var state: AppState

    let target: BackgroundTarget
    let name: String
    let icon: NSImage?
    /// Executable path for CLI processes, or nil for menu bar apps.
    let detail: String?
    let strings: Strings
    /// CPU activity for CLI processes; nil for menu bar apps and unsampled ones.
    var activity: BackgroundActivity?
    /// Rendered but not controllable, with an explanation in the section footer.
    var isExcluded: Bool = false
    /// Not running right now; the switch removes it from the list instead of
    /// adding it, so the row reads differently.
    var isDormant: Bool = false

    @State private var isHovered = false

    /// Read live state, not a snapshot taken when the row was built: `@Published`
    /// notifies before the value changes, so a captured copy renders one step
    /// behind and makes the switch jump back.
    private var isBlacklisted: Bool {
        state.isBackgroundBlacklisted(target)
    }

    private func apply(_ isOn: Bool) {
        state.setBackgroundBlacklisted(isOn, target: target)
    }

    private var activityLabel: String {
        switch activity {
        case .active(let cpu):
            return "\(strings.backgroundActive) \(Int(cpu.rounded()))%"
        case .idle:
            return strings.backgroundIdle
        case nil:
            return ""
        }
    }

    private var activityColor: Color {
        switch activity {
        case .active: return .orange
        case .idle: return .secondary
        case nil: return .clear
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                iconView

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(name)
                            .lineLimit(1)
                        if activity != nil && !isExcluded {
                            Text(activityLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(activityColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(activityColor.opacity(0.14))
                                )
                        }
                    }
                    HStack(spacing: 6) {
                        if isExcluded {
                            Text(strings.backgroundAncestorStatus)
                                .foregroundStyle(.secondary)
                        } else if isDormant {
                            Text(strings.backgroundNotRunning)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(isBlacklisted ? strings.backgroundBlacklisted : strings.backgroundKept)
                                .foregroundStyle(isBlacklisted ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                        }
                        if let detail {
                            Text(detail)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !isExcluded { apply(!isBlacklisted) } }

            Toggle("", isOn: Binding(
                get: { isBlacklisted },
                set: { apply($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(isExcluded)
            .help(isDormant ? strings.removeFromListHint : strings.closeBackgroundAppsHint)
            .accessibilityLabel(name)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .opacity(isExcluded ? 0.6 : 1)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered && !isExcluded ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 24, height: 24)
                .opacity(isBlacklisted ? 1 : 0.5)
        } else {
            // CLI processes have no app icon; a terminal glyph keeps the rows aligned.
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isBlacklisted ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.08))
                )
        }
    }
}
