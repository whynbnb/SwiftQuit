import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(state.strings.general, systemImage: "gearshape")
                }
            AppsSettingsView()
                .tabItem {
                    Label(state.strings.appsTab, systemImage: "checklist")
                }
        }
        .frame(width: 480, height: 420)
        .background(WindowTitleAccessor(title: state.strings.settingsTitle))
    }
}

/// Keeps the Settings window title in sync with the in-app language.
private struct WindowTitleAccessor: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.title = title
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.title = title
        }
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var state: AppState

    private let presets: [Int] = [15, 30, 60, 120, 240, 480, 1440]

    private var strings: Strings { state.strings }

    var body: some View {
        Form {
            Section {
                Toggle(strings.enableAutoQuit, isOn: $state.isAutoQuitEnabled)

                LabeledContent {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(presets, id: \.self) { minutes in
                                Button(strings.duration(minutes: minutes)) {
                                    state.idleMinutes = Double(minutes)
                                }
                            }
                        } label: {
                            Text(strings.duration(minutes: Int(state.idleMinutes)))
                                .monospacedDigit()
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Stepper("", value: $state.idleMinutes, in: 5...1440, step: 5)
                            .labelsHidden()
                    }
                } label: {
                    Text(strings.idleThreshold)
                }
                .disabled(!state.isAutoQuitEnabled)
            } header: {
                Text(strings.autoQuit)
            }

            Section {
                Toggle(strings.launchAtLogin, isOn: $state.launchAtLogin)
                if state.launchAtLoginFailed {
                    Text(strings.loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                Picker(selection: $state.language) {
                    Text(strings.followSystem).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("中文").tag(AppLanguage.chinese)
                } label: {
                    Text(strings.languageTitle)
                }
                Text(strings.languageNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsSettingsView: View {
    @EnvironmentObject private var state: AppState

    private var strings: Strings { state.strings }

    private var apps: [AppInfo] {
        state.displayedApps
    }

    private var includedCount: Int {
        apps.filter { !state.excludedBundleIDs.contains($0.bundleID) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(strings.appsSummary(
                        included: includedCount,
                        total: apps.count,
                        idle: strings.duration(minutes: Int(state.idleMinutes))
                    ))
                    .font(.system(size: 12, weight: .medium))

                    Spacer()

                    Toggle(strings.showFinder, isOn: $state.showFinder)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Text(strings.appsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if apps.isEmpty {
                Spacer()
                Text(strings.noRunningApps)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(apps) { app in
                    AppToggleRow(
                        app: app,
                        strings: strings,
                        isIncluded: !state.excludedBundleIDs.contains(app.bundleID)
                    ) {
                        toggle(app)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func toggle(_ app: AppInfo) {
        if state.excludedBundleIDs.contains(app.bundleID) {
            state.excludedBundleIDs.remove(app.bundleID)
        } else {
            state.excludedBundleIDs.insert(app.bundleID)
        }
    }
}

/// One row of the Apps tab: the checkbox/switch means "this app auto-quits when idle".
private struct AppToggleRow: View {
    let app: AppInfo
    let strings: Strings
    let isIncluded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    private var statusText: String {
        guard isIncluded else { return strings.keepRunningStatus }
        return app.bundleID == SystemApps.finderBundleID
            ? strings.closeWindowsStatus
            : strings.autoQuitStatus
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .opacity(isIncluded ? 1 : 0.5)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(isIncluded ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .help(strings.includeInAutoQuitHint)

            Toggle("", isOn: Binding(
                get: { isIncluded },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(strings.includeInAutoQuitHint)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}
