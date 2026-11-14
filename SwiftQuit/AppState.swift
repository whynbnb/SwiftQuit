import SwiftUI
import Combine
import OSLog

enum QuitReason: String, Codable, Sendable {
    case idle
    case manual
    case windows
}

struct QuitEvent: Identifiable, Codable, Sendable {
    var id = UUID()
    let date: Date
    let appName: String
    let bundleID: String
    let reason: QuitReason
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// How long to wait before retrying a quit request that an app appears to have ignored.
    private static let quitRetryInterval: TimeInterval = 30
    private static let historyLimit = 100

    @Published var runningApps: [AppInfo] = []
    @Published var excludedBundleIDs: Set<String> = [] {
        didSet { saveExcluded(); rebuildTimers() }
    }
    @Published var idleMinutes: Double = 60 {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: "idleMinutes"); rebuildTimers() }
    }
    @Published var isAutoQuitEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isAutoQuitEnabled, forKey: "isAutoQuitEnabled")
            if !isAutoQuitEnabled { cancelAllPendingQuits() }
            rebuildTimers()
        }
    }
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != LaunchAtLoginManager.shared.isEnabled else { return }
            if LaunchAtLoginManager.shared.setEnabled(launchAtLogin) {
                launchAtLoginFailed = false
            } else {
                launchAtLoginFailed = true
                launchAtLogin = LaunchAtLoginManager.shared.isEnabled
            }
        }
    }
    @Published var launchAtLoginFailed = false
    @Published var language: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            notifier.configure(strings: strings)
        }
    }
    /// Whether Finder is listed. Finder is never quit; its windows are closed instead.
    @Published var showFinder: Bool = true {
        didSet { UserDefaults.standard.set(showFinder, forKey: "showFinder") }
    }
    @Published var pausedUntil: Date? {
        didSet { savePauseState() }
    }
    /// Per-app idle thresholds in minutes; apps without an entry use `idleMinutes`.
    @Published var customThresholds: [String: Double] = [:] {
        didSet { UserDefaults.standard.set(customThresholds, forKey: "customThresholds") }
    }
    @Published var gracePeriod: Double = 10 {
        didSet { UserDefaults.standard.set(gracePeriod, forKey: "gracePeriod") }
    }
    @Published var skipAudioApps: Bool = true {
        didSet { UserDefaults.standard.set(skipAudioApps, forKey: "skipAudioApps") }
    }
    @Published var history: [QuitEvent] = []

    @Published var foregroundBundleID: String = "" {
        didSet { touchForeground() }
    }
    @Published var remainingSeconds: [String: Double] = [:]
    /// Apps that are inside the pre-quit grace period.
    @Published var pendingQuits: Set<String> = []
    @Published var pauseRemaining: TimeInterval = 0

    /// User-facing strings for the selected language.
    var strings: Strings { Strings(language: language) }

    /// Apps shown in the popover and settings, honoring the Finder visibility setting.
    var displayedApps: [AppInfo] {
        guard !showFinder else { return runningApps }
        return runningApps.filter { $0.bundleID != SystemApps.finderBundleID }
    }

    var isPaused: Bool { pausedUntil != nil }

    /// Set by the app delegate so SwiftUI views can open the settings window.
    var openSettingsAction: (() -> Void)?

    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "AppState")
    private let notifier = QuitNotifier()
    private let audioMonitor = AudioActivityMonitor()
    private var monitor: AppMonitor!
    private var quitManager: QuitManager!
    private var lastActiveDates: [String: Date] = [:]
    private var quitRequests: [String: Date] = [:]
    private var graceDeadlines: [String: Date] = [:]
    private var tickTimer: Timer?
    private var prevForeground: String = ""
    private var pauseStartedAt: Date?
    private var audioBundleIDs: Set<String> = []
    private var lastAudioRefresh: Date = .distantPast

    private init() {
        idleMinutes = UserDefaults.standard.object(forKey: "idleMinutes") as? Double ?? 60
        isAutoQuitEnabled = UserDefaults.standard.object(forKey: "isAutoQuitEnabled") as? Bool ?? true
        excludedBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        showFinder = UserDefaults.standard.object(forKey: "showFinder") as? Bool ?? true
        customThresholds = UserDefaults.standard.dictionary(forKey: "customThresholds") as? [String: Double] ?? [:]
        gracePeriod = UserDefaults.standard.object(forKey: "gracePeriod") as? Double ?? 10
        skipAudioApps = UserDefaults.standard.object(forKey: "skipAudioApps") as? Bool ?? true
        launchAtLogin = LaunchAtLoginManager.shared.isEnabled
        history = Self.loadHistory()

        if let stamp = UserDefaults.standard.object(forKey: "pausedUntil") as? Double {
            let until = Date(timeIntervalSince1970: stamp)
            if until > Date() {
                pausedUntil = until
                if let start = UserDefaults.standard.object(forKey: "pauseStartedAt") as? Double {
                    pauseStartedAt = Date(timeIntervalSince1970: start)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "pausedUntil")
                UserDefaults.standard.removeObject(forKey: "pauseStartedAt")
            }
        }

        monitor = AppMonitor { @MainActor [weak self] apps, fg in
            self?.runningApps = apps
            self?.foregroundBundleID = fg
        }
        quitManager = QuitManager()

        notifier.configure(strings: Strings(language: language))
        notifier.requestAuthorization()
        notifier.onKeepRunning = { [weak self] bundleID in
            self?.keepRunning(bundleID: bundleID)
        }
    }

    // MARK: - Control

    func openSettings() {
        openSettingsAction?()
    }

    func quitNow(_ app: AppInfo) {
        cancelPendingQuit(app.bundleID)
        let handled = quitManager.quit(app)
        if app.bundleID == SystemApps.finderBundleID {
            // Finder stays running, so restart its idle countdown after closing windows.
            lastActiveDates[app.bundleID] = Date()
            quitRequests[app.bundleID] = nil
            if handled { record(app, reason: .windows) }
        } else {
            quitRequests[app.bundleID] = Date()
            if handled { record(app, reason: .manual) }
        }
    }

    func keepRunning(bundleID: String) {
        lastActiveDates[bundleID] = Date()
        cancelPendingQuit(bundleID)
    }

    func startMonitoring() {
        monitor.start()
        rebuildTimers()
    }

    func stopMonitoring() {
        monitor.stop()
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Pause

    func pauseForOneHour() {
        pause(until: Date().addingTimeInterval(3600))
    }

    func pauseUntilTomorrow() {
        let calendar = Calendar.current
        let tomorrow = calendar.startOfDay(for: Date().addingTimeInterval(86_400))
        pause(until: tomorrow)
    }

    func pause(until date: Date) {
        let now = Date()
        guard date > now else { return }
        if pauseStartedAt == nil { pauseStartedAt = now }
        cancelAllPendingQuits()
        pausedUntil = date
        pauseRemaining = date.timeIntervalSince(now)
        UserDefaults.standard.set(pauseStartedAt?.timeIntervalSince1970, forKey: "pauseStartedAt")
    }

    func resumePause() {
        if let started = pauseStartedAt {
            let delta = Date().timeIntervalSince(started)
            if delta > 0 {
                // Time spent paused should not count towards idleness.
                for (bundleID, date) in lastActiveDates {
                    lastActiveDates[bundleID] = date.addingTimeInterval(delta)
                }
            }
        }
        pauseStartedAt = nil
        pauseRemaining = 0
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: "pauseStartedAt")
    }

    private func savePauseState() {
        if let pausedUntil {
            UserDefaults.standard.set(pausedUntil.timeIntervalSince1970, forKey: "pausedUntil")
        } else {
            UserDefaults.standard.removeObject(forKey: "pausedUntil")
        }
    }

    // MARK: - Per-app thresholds

    func thresholdMinutes(for bundleID: String) -> Double {
        customThresholds[bundleID] ?? idleMinutes
    }

    func setThreshold(_ minutes: Double?, for bundleID: String) {
        if let minutes {
            customThresholds[bundleID] = minutes
        } else {
            customThresholds.removeValue(forKey: bundleID)
        }
    }

    // MARK: - History

    func clearHistory() {
        history.removeAll()
        UserDefaults.standard.removeObject(forKey: "quitHistory")
    }

    private func record(_ app: AppInfo, reason: QuitReason) {
        history.insert(
            QuitEvent(date: Date(), appName: app.name, bundleID: app.bundleID, reason: reason),
            at: 0
        )
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "quitHistory")
        }
    }

    private static func loadHistory() -> [QuitEvent] {
        guard let data = UserDefaults.standard.data(forKey: "quitHistory"),
              let events = try? JSONDecoder().decode([QuitEvent].self, from: data)
        else { return [] }
        return events
    }

    // MARK: - Timers

    private func touchForeground() {
        guard foregroundBundleID != prevForeground else { return }
        if !prevForeground.isEmpty {
            lastActiveDates[prevForeground] = Date()
        }
        if !foregroundBundleID.isEmpty {
            // The app is active again, so drop any pending quit for it.
            lastActiveDates[foregroundBundleID] = Date()
            quitRequests[foregroundBundleID] = nil
            cancelPendingQuit(foregroundBundleID)
        }
        prevForeground = foregroundBundleID
    }

    private func rebuildTimers() {
        tickTimer?.invalidate()
        guard isAutoQuitEnabled else {
            remainingSeconds = [:]
            return
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = Date()

        if let until = pausedUntil {
            if until > now {
                pauseRemaining = until.timeIntervalSince(now)
                remainingSeconds = [:]
                return
            }
            resumePause()
        }
        pauseRemaining = 0

        if skipAudioApps, now.timeIntervalSince(lastAudioRefresh) >= 2 {
            audioBundleIDs = audioMonitor.activeBundleIDs()
            lastAudioRefresh = now
        }

        var updated: [String: Double] = [:]
        var runningBundleIDs = Set<String>()
        var stillPending = Set<String>()

        for app in runningApps {
            let bundleID = app.bundleID
            runningBundleIDs.insert(bundleID)
            guard bundleID != SystemApps.selfBundleID else { continue }

            if bundleID == SystemApps.finderBundleID && !showFinder {
                lastActiveDates[bundleID] = now
                dropPending(bundleID)
                continue
            }

            if excludedBundleIDs.contains(bundleID) {
                // Keep the clock fresh so re-enabling an app starts a full countdown.
                lastActiveDates[bundleID] = now
                dropPending(bundleID)
                continue
            }

            if bundleID == foregroundBundleID {
                lastActiveDates[bundleID] = now
                dropPending(bundleID)
                continue
            }

            if skipAudioApps, audioBundleIDs.contains(bundleID) {
                // Playing audio or in a call: keep the clock fresh and never quit.
                lastActiveDates[bundleID] = now
                dropPending(bundleID)
                continue
            }

            // Track apps we discover after launch (including ones that were already
            // running in the background) so the countdown actually starts.
            if lastActiveDates[bundleID] == nil {
                lastActiveDates[bundleID] = now
            }
            let threshold = thresholdMinutes(for: bundleID) * 60
            let lastActive = lastActiveDates[bundleID] ?? now
            let remaining = max(0, threshold - now.timeIntervalSince(lastActive))

            if remaining > 0 {
                updated[bundleID] = remaining
                dropPending(bundleID)
                continue
            }

            if let deadline = graceDeadlines[bundleID] {
                if now < deadline {
                    updated[bundleID] = deadline.timeIntervalSince(now)
                    stillPending.insert(bundleID)
                } else {
                    performQuit(app, reason: reason(for: app))
                    finishHandledQuit(app, threshold: threshold, now: now, updated: &updated)
                }
                continue
            }

            guard shouldRequestQuit(bundleID, now: now) else {
                updated[bundleID] = 0
                continue
            }

            if gracePeriod > 0 {
                startGrace(for: app, now: now)
                updated[bundleID] = gracePeriod
                stillPending.insert(bundleID)
            } else {
                performQuit(app, reason: reason(for: app))
                finishHandledQuit(app, threshold: threshold, now: now, updated: &updated)
            }
        }

        let stale = graceDeadlines.keys.filter { !runningBundleIDs.contains($0) }
        for bundleID in stale {
            notifier.clear(bundleID: bundleID)
            graceDeadlines.removeValue(forKey: bundleID)
        }

        pendingQuits = stillPending
        lastActiveDates = lastActiveDates.filter { runningBundleIDs.contains($0.key) }
        quitRequests = quitRequests.filter { runningBundleIDs.contains($0.key) }
        remainingSeconds = updated
    }

    private func reason(for app: AppInfo) -> QuitReason {
        app.bundleID == SystemApps.finderBundleID ? .windows : .idle
    }

    private func finishHandledQuit(_ app: AppInfo, threshold: Double, now: Date, updated: inout [String: Double]) {
        if app.bundleID == SystemApps.finderBundleID {
            // Finder cannot quit: close its windows and start a fresh cycle.
            lastActiveDates[app.bundleID] = now
            updated[app.bundleID] = threshold
        } else {
            updated[app.bundleID] = 0
        }
    }

    private func startGrace(for app: AppInfo, now: Date) {
        graceDeadlines[app.bundleID] = now.addingTimeInterval(gracePeriod)
        let seconds = Int(gracePeriod.rounded())
        if app.bundleID == SystemApps.finderBundleID {
            notifier.notify(
                bundleID: app.bundleID,
                title: strings.notificationTitleCloseWindows,
                body: strings.notificationBodyClosingWindows(seconds: seconds)
            )
        } else {
            notifier.notify(
                bundleID: app.bundleID,
                title: strings.notificationTitle(app: app.name),
                body: strings.notificationBody(seconds: seconds)
            )
        }
        logger.debug("Started grace period for \(app.name, privacy: .public)")
    }

    private func performQuit(_ app: AppInfo, reason: QuitReason) {
        let handled = quitManager.quit(app)
        if graceDeadlines.removeValue(forKey: app.bundleID) != nil {
            pendingQuits.remove(app.bundleID)
            notifier.clear(bundleID: app.bundleID)
        }
        quitRequests[app.bundleID] = Date()
        if handled {
            record(app, reason: reason)
            logger.debug("Handled \(app.name, privacy: .public) (\(reason.rawValue, privacy: .public))")
        }
    }

    private func dropPending(_ bundleID: String) {
        if graceDeadlines.removeValue(forKey: bundleID) != nil {
            notifier.clear(bundleID: bundleID)
        }
    }

    private func cancelPendingQuit(_ bundleID: String) {
        guard graceDeadlines.removeValue(forKey: bundleID) != nil else {
            pendingQuits.remove(bundleID)
            return
        }
        pendingQuits.remove(bundleID)
        notifier.clear(bundleID: bundleID)
    }

    private func cancelAllPendingQuits() {
        for bundleID in graceDeadlines.keys {
            notifier.clear(bundleID: bundleID)
        }
        graceDeadlines.removeAll()
        pendingQuits.removeAll()
    }

    private func shouldRequestQuit(_ bundleID: String, now: Date) -> Bool {
        guard let requestedAt = quitRequests[bundleID] else { return true }
        return now.timeIntervalSince(requestedAt) >= Self.quitRetryInterval
    }

    private func saveExcluded() {
        UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")
    }
}
