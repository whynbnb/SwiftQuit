import SwiftUI

struct GeneralSettingsView: View {
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

                Picker(selection: $state.gracePeriod) {
                    Text(strings.graceOption(seconds: 0)).tag(0.0)
                    Text(strings.graceOption(seconds: 10)).tag(10.0)
                    Text(strings.graceOption(seconds: 30)).tag(30.0)
                    Text(strings.graceOption(seconds: 60)).tag(60.0)
                } label: {
                    Text(strings.gracePeriod)
                }
                .disabled(!state.isAutoQuitEnabled)

                Toggle(strings.skipAudioApps, isOn: $state.skipAudioApps)
                    .disabled(!state.isAutoQuitEnabled)
            } header: {
                Text(strings.autoQuit)
            }

            Section {
                Toggle(strings.quietHoursEnabled, isOn: $state.quietHoursEnabled)
                    .disabled(!state.isAutoQuitEnabled)

                LabeledContent {
                    HStack(spacing: 6) {
                        hourPicker(selection: $state.quietStartHour)
                        Text(strings.quietHoursRange)
                            .foregroundStyle(.secondary)
                        hourPicker(selection: $state.quietEndHour)
                    }
                } label: {
                    Text(strings.quietHoursWindow)
                }
                .disabled(!state.isAutoQuitEnabled || !state.quietHoursEnabled)

                Toggle(strings.quietWeekdaysOnly, isOn: $state.quietWeekdaysOnly)
                    .disabled(!state.isAutoQuitEnabled || !state.quietHoursEnabled)
            } header: {
                Text(strings.quietHoursSection)
            } footer: {
                Text(strings.quietHoursNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle(strings.useSystemIdle, isOn: $state.useSystemIdle)
                    .disabled(!state.isAutoQuitEnabled)

                LabeledContent {
                    HStack(spacing: 6) {
                        Menu {
                            ForEach(presets, id: \.self) { minutes in
                                Button(strings.duration(minutes: minutes)) {
                                    state.systemIdleMinutes = Double(minutes)
                                }
                            }
                        } label: {
                            Text(strings.duration(minutes: Int(state.systemIdleMinutes)))
                                .monospacedDigit()
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()

                        Stepper("", value: $state.systemIdleMinutes, in: 5...480, step: 5)
                            .labelsHidden()
                    }
                } label: {
                    Text(strings.systemIdleThreshold)
                }
                .disabled(!state.isAutoQuitEnabled || !state.useSystemIdle)
            } header: {
                Text(strings.systemIdleSection)
            } footer: {
                Text(strings.systemIdleNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent {
                    pauseControls
                } label: {
                    Text(strings.pauseAutoQuit)
                }
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
            } footer: {
                Text(strings.languageNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func hourPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
        .labelsHidden()
        .frame(width: 84)
    }

    @ViewBuilder
    private var pauseControls: some View {
        if let until = state.pausedUntil {
            HStack(spacing: 8) {
                Text(strings.pausedUntilLabel(time: until.formatted(date: .omitted, time: .shortened)))
                    .foregroundStyle(.secondary)
                Button(strings.resumeNow) {
                    state.resumePause()
                }
            }
        } else {
            HStack(spacing: 8) {
                Button(strings.pauseOneHour) {
                    state.pauseForOneHour()
                }
                .frame(minWidth: 110)
                Button(strings.pauseUntilTomorrow) {
                    state.pauseUntilTomorrow()
                }
                .frame(minWidth: 110)
            }
        }
    }
}

struct AppsSettingsView: View {
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
                    Text(strings.appsSummary(included: includedCount, total: apps.count))
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
                        isIncluded: !state.excludedBundleIDs.contains(app.bundleID),
                        globalMinutes: state.idleMinutes,
                        customMinutes: state.customThresholds[app.bundleID],
                        onToggle: { toggle(app) },
                        onSetThreshold: { state.setThreshold($0, for: app.bundleID) }
                    )
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

/// One row of the Apps tab: the switch means "this app auto-quits when idle".
private struct AppToggleRow: View {
    let app: AppInfo
    let strings: Strings
    let isIncluded: Bool
    let globalMinutes: Double
    let customMinutes: Double?
    let onToggle: () -> Void
    let onSetThreshold: (Double?) -> Void

    @State private var isHovered = false

    private let presets: [Int] = [15, 30, 60, 120, 240, 480, 1440]

    private var statusText: String {
        guard isIncluded else { return strings.keepRunningStatus }
        return app.bundleID == SystemApps.finderBundleID
            ? strings.closeWindowsStatus
            : strings.autoQuitStatus
    }

    private var thresholdLabel: String {
        guard let customMinutes else { return strings.useGlobalShort }
        return strings.duration(minutes: Int(customMinutes))
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

            Menu {
                Button(strings.useGlobalThreshold(duration: strings.duration(minutes: Int(globalMinutes)))) {
                    onSetThreshold(nil)
                }
                Divider()
                ForEach(presets, id: \.self) { minutes in
                    Button(strings.duration(minutes: minutes)) {
                        onSetThreshold(Double(minutes))
                    }
                }
            } label: {
                Text(thresholdLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!isIncluded)
            .help(strings.idleThreshold)

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
