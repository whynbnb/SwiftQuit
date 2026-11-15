import SwiftUI
import Combine
import OSLog

enum QuitReason: String, Codable, Sendable {
    case idle
    case manual
    case windows
    /// Quit by the manual "close background apps" sweep.
    case background
}

struct QuitEvent: Identifiable, Codable, Sendable {
    var id = UUID()
    let date: Date
    let appName: String
    let bundleID: String
    let reason: QuitReason
}

/// The app that will be quit next, used to drive the menu bar hourglass.
struct NextQuit {
    let app: AppInfo
    /// Remaining time as a fraction of that app's threshold (0...1).
    let fraction: Double
    let remaining: TimeInterval
}

/// Settings tabs, so callers can jump to a specific pane.
enum SettingsTab: Int, Sendable {
    case general
    case apps
    case background
    case history
}

/// Identifies one entry in the background clean-up list.
///
/// The list holds two quite different things: menu bar agents, which are GUI
/// apps and can be reached through `NSRunningApplication`, and command line
/// processes (`herdr`, `opencode`, a Java daemon), which only exist in the BSD
/// process table. Each is keyed by what actually identifies it.
enum BackgroundTarget: Hashable, Codable, Sendable {
    /// A menu bar app, keyed by bundle ID.
    case app(bundleID: String)
    /// A CLI process or daemon, keyed by its executable path.
    case process(path: String)
}

/// One row of the background list, saved so the entry survives the app quitting.
struct BackgroundEntry: Codable, Hashable, Identifiable {
    let target: BackgroundTarget
    let name: String

    var id: String {
        switch target {
        case .app(let bundleID): return "app:" + bundleID
        case .process(let path): return "process:" + path
        }
    }
}

/// One row of the background clean-up list, ready to render.
enum BackgroundItem: Identifiable, Hashable {
    /// A menu bar app that can be quit through NSRunningApplication.
    case app(AppInfo)
    /// A CLI process group keyed by executable path.
    case process(BackgroundProcess)

    var id: String {
        switch self {
        case .app(let app): return "app:" + app.bundleID
        case .process(let group): return "process:" + group.id
        }
    }

    var name: String {
        switch self {
        case .app(let app): return app.name
        case .process(let group): return group.name
        }
    }

    var icon: NSImage? {
        switch self {
        case .app(let app): return app.icon
        case .process: return nil
        }
    }

    var target: BackgroundTarget {
        switch self {
        case .app(let app): return .app(bundleID: app.bundleID)
        case .process(let group): return .process(path: group.id)
        }
    }

    /// Extra detail shown under the name: the executable path for CLI processes,
    /// "N processes" when a tool runs several instances.
    var detail: String? {
        switch self {
        case .app: return nil
        case .process(let group):
            if group.processCount > 1 { return "\(group.displayPath) · \(group.processCount)" }
            return group.displayPath
        }
    }

    /// Compact count shown in the popover, e.g. "×3" for a tool with 3 processes.
    var processCountLabel: String? {
        guard case .process(let group) = self, group.processCount > 1 else { return nil }
        return "×\(group.processCount)"
    }

    /// Whether this item looks busy right now. Menu bar apps are not measured.
    var isActive: Bool {
        guard case .process(let group) = self else { return false }
        return group.isActive
    }

    var hasActivitySample: Bool {
        guard case .process(let group) = self else { return false }
        return group.hasActivitySample
    }

    var cpuPercent: Double? {
        guard case .process(let group) = self, group.hasActivitySample else { return nil }
        return group.cpuPercent
    }
}

/// Outcome of one manual "close background apps" sweep.
struct BackgroundCleanupResult: Equatable {
    let date: Date
    /// Items confirmed gone after the sweep.
    let quitCount: Int
    /// Items that ignored the request and are still running.
    let stubbornCount: Int
    /// Items left alone because they were busy with real work.
    let skippedActiveCount: Int
    let keptCount: Int

    var totalToClose: Int { quitCount + stubbornCount }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// How long to wait before retrying a quit request that an app appears to have ignored.
    private static let quitRetryInterval: TimeInterval = 30
    /// After this long without the app exiting, it is treated as unresponsive so
    /// the UI can offer a force quit instead of spinning forever.
    private static let unresponsiveTimeout: TimeInterval = 8
    private static let historyLimit = 100
    /// The countdown timer fires once a second. A longer pause means the process
    /// was suspended (typically system sleep), not that time passed normally.
    private static let tickInterval: TimeInterval = 1
    private static let maximumTickGap: TimeInterval = 30

    @Published var runningApps: [AppInfo] = []
    /// Menu bar apps: GUI agents that can be reached through NSRunningApplication.
    @Published var backgroundApps: [AppInfo] = [] {
        didSet { resolveBackgroundNames() }
    }
    /// Command line processes and daemons, which have no NSRunningApplication.
    @Published var backgroundProcesses: [BackgroundProcess] = [] {
        didSet { resolveBackgroundNames() }
    }
    /// CLI processes skipped because SwiftQuit is currently running inside them.
    @Published var ancestorProcesses: [BackgroundProcess] = []
    @Published var excludedBundleIDs: Set<String> = [] {
        didSet { saveExcluded(); rebuildTimers() }
    }
    /// Background apps that the manual sweep should quit. Everything else is kept.
    @Published var backgroundBlacklist: [BackgroundEntry] = [] {
        didSet {
            saveBackgroundBlacklist()
            resolveBackgroundNames()
        }
    }
    /// Result of the most recent manual background sweep, for inline feedback.
    @Published var lastBackgroundCleanup: BackgroundCleanupResult?
    /// True while a sweep waits for the apps to exit.
    @Published var isBackgroundSweepInFlight = false
    /// Skip items that are busy with real work instead of stopping them.
    /// Off by default: the original behaviour stops everything blacklisted.
    @Published var skipActiveBackgroundItems: Bool = false {
        didSet { UserDefaults.standard.set(skipActiveBackgroundItems, forKey: "skipActiveBackgroundItems") }
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
    /// Also let the frontmost app be cleaned up once the user has not touched the
    /// Mac for a while. Off by default: normally the app in use is never quit.
    @Published var useSystemIdle: Bool = false {
        didSet { UserDefaults.standard.set(useSystemIdle, forKey: "useSystemIdle") }
    }
    /// How long without keyboard or mouse input before the frontmost app counts
    /// as idle too.
    @Published var systemIdleMinutes: Double = 30 {
        didSet { UserDefaults.standard.set(systemIdleMinutes, forKey: "systemIdleMinutes") }
    }
    /// Seconds since the last user input, refreshed on every tick for display.
    @Published var systemIdleSeconds: TimeInterval = 0
    /// Do not quit anything inside a daily time window, e.g. working hours.
    @Published var quietHoursEnabled: Bool = false {
        didSet { UserDefaults.standard.set(quietHoursEnabled, forKey: "quietHoursEnabled") }
    }
    @Published var quietStartHour: Int = 9 {
        didSet { UserDefaults.standard.set(quietStartHour, forKey: "quietStartHour") }
    }
    @Published var quietEndHour: Int = 18 {
        didSet { UserDefaults.standard.set(quietEndHour, forKey: "quietEndHour") }
    }
    /// Restrict the window to Monday–Friday.
    @Published var quietWeekdaysOnly: Bool = false {
        didSet { UserDefaults.standard.set(quietWeekdaysOnly, forKey: "quietWeekdaysOnly") }
    }
    @Published var history: [QuitEvent] = []

    @Published var foregroundBundleID: String = "" {
        didSet { touchForeground() }
    }
    @Published var remainingSeconds: [String: Double] = [:]
    /// Apps that are inside the pre-quit grace period.
    @Published var pendingQuits: Set<String> = []
    /// Apps that were asked to quit but are still running, so the UI can offer a
    /// force quit instead of spinning forever.
    @Published var unresponsiveApps: Set<String> = []
    @Published var pauseRemaining: TimeInterval = 0

    /// User-facing strings for the selected language.
    var strings: Strings { Strings(language: language) }

    /// Apps shown in the popover and settings, honoring the Finder visibility setting.
    var displayedApps: [AppInfo] {
        guard !showFinder else { return runningApps }
        return runningApps.filter { $0.bundleID != SystemApps.finderBundleID }
    }

    // MARK: - Background list

    /// Every background item the sweep can act on, menu bar apps and CLI
    /// processes alike, as one uniform list.
    var backgroundItems: [BackgroundItem] {
        backgroundApps.map(BackgroundItem.app) + backgroundProcesses.map(BackgroundItem.process)
    }

    /// Items that are running right now and are not blacklisted.
    var keptBackgroundItems: [BackgroundItem] {
        backgroundItems.filter { !isBackgroundBlacklisted($0.target) }
    }

    /// Items the sweep would stop right now.
    var blacklistedBackgroundItems: [BackgroundItem] {
        backgroundItems.filter { isBackgroundBlacklisted($0.target) }
    }

    /// Number of distinct background items currently running.
    var runningBackgroundCount: Int { backgroundItems.count }

    /// Blacklisted entries whose process is not running (or whose app is closed).
    var dormantBlacklistedEntries: [BackgroundEntry] {
        let running = Set(backgroundItems.map(\.target))
        return backgroundBlacklist.filter { !running.contains($0.target) }
    }

    var isPaused: Bool { pausedUntil != nil }

    /// True inside the configured quiet window, where nothing is quit even if the
    /// countdown reaches zero.
    var isInQuietHours: Bool {
        quietHoursEnabled && Self.isQuietHour(
            date: Date(),
            startHour: quietStartHour,
            endHour: quietEndHour,
            weekdaysOnly: quietWeekdaysOnly
        )
    }

    /// Published copy of `isInQuietHours`, refreshed on every tick so the UI can
    /// react to the window opening and closing.
    @Published var isQuietPeriod = false

    /// Whether `date` falls in [startHour, endHour). A window that ends before it
    /// starts is treated as overnight, e.g. 22 → 7.
    static func isQuietHour(date: Date, startHour: Int, endHour: Int, weekdaysOnly: Bool) -> Bool {
        guard startHour != endHour else { return false }
        let calendar = Calendar.current
        if weekdaysOnly {
            let weekday = calendar.component(.weekday, from: date)
            // 1 = Sunday, 7 = Saturday
            guard weekday != 1, weekday != 7 else { return false }
        }
        let hour = calendar.component(.hour, from: date)
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        return hour >= startHour || hour < endHour
    }

    /// The managed app closest to being quit, if any.
    var nextQuit: NextQuit? {
        var best: NextQuit?
        for app in displayedApps {
            guard let remaining = remainingSeconds[app.bundleID] else { continue }
            let threshold = max(1, thresholdMinutes(for: app.bundleID) * 60)
            let fraction = min(1, max(0, remaining / threshold))
            if best == nil || fraction < best!.fraction {
                best = NextQuit(app: app, fraction: fraction, remaining: remaining)
            }
        }
        return best
    }

    /// Set by the app delegate so SwiftUI views can open the settings window.
    var openSettingsAction: (() -> Void)?
    /// Opens the settings window on a specific tab.
    var openSettingsTabAction: ((SettingsTab) -> Void)?

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
    private var isResolvingBackgroundNames = false
    /// When the last tick actually ran, used to spot suspended time.
    private var lastTickDate: Date?
    /// Sleep start, reported by the workspace, so the sleep duration can be
    /// excluded from idleness even if no tick ran while asleep.
    private var sleepStartedAt: Date?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        idleMinutes = UserDefaults.standard.object(forKey: "idleMinutes") as? Double ?? 60
        isAutoQuitEnabled = UserDefaults.standard.object(forKey: "isAutoQuitEnabled") as? Bool ?? true
        excludedBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        backgroundBlacklist = Self.loadBackgroundBlacklist()
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        showFinder = UserDefaults.standard.object(forKey: "showFinder") as? Bool ?? true
        customThresholds = UserDefaults.standard.dictionary(forKey: "customThresholds") as? [String: Double] ?? [:]
        gracePeriod = UserDefaults.standard.object(forKey: "gracePeriod") as? Double ?? 10
        skipAudioApps = UserDefaults.standard.object(forKey: "skipAudioApps") as? Bool ?? true
        skipActiveBackgroundItems = UserDefaults.standard.object(forKey: "skipActiveBackgroundItems") as? Bool ?? false
        useSystemIdle = UserDefaults.standard.object(forKey: "useSystemIdle") as? Bool ?? false
        systemIdleMinutes = UserDefaults.standard.object(forKey: "systemIdleMinutes") as? Double ?? 30
        quietHoursEnabled = UserDefaults.standard.object(forKey: "quietHoursEnabled") as? Bool ?? false
        quietStartHour = UserDefaults.standard.object(forKey: "quietStartHour") as? Int ?? 9
        quietEndHour = UserDefaults.standard.object(forKey: "quietEndHour") as? Int ?? 18
        quietWeekdaysOnly = UserDefaults.standard.object(forKey: "quietWeekdaysOnly") as? Bool ?? false
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

        monitor = AppMonitor { @MainActor [weak self] apps, background, processes, ancestors, fg in
            self?.runningApps = apps
            self?.backgroundApps = background
            self?.backgroundProcesses = processes
            self?.ancestorProcesses = ancestors
            self?.foregroundBundleID = fg
        }
        quitManager = QuitManager()

        notifier.configure(strings: Strings(language: language))
        notifier.requestAuthorization()
        notifier.onKeepRunning = { [weak self] bundleID in
            self?.keepRunning(bundleID: bundleID)
        }

        observeSystemSleep()
    }

    // MARK: - Sleep

    private func observeSystemSleep() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepStartedAt = Date() }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })
    }

    /// Time spent asleep must not count as idle time. Without this, waking after
    /// a long sleep makes every app look overdue and they are all quit at once.
    private func systemDidWake() {
        defer { sleepStartedAt = nil }
        guard let started = sleepStartedAt else { return }
        let slept = Date().timeIntervalSince(started)
        guard slept > 1 else { return }
        shiftIdleClocks(by: slept)
        lastTickDate = Date()
        lastAudioRefresh = .distantPast
        logger.debug("Woke after \(slept, privacy: .public)s asleep; idleness clocks shifted")
    }

    /// Moves every idle deadline forward, so a suspended period is treated like
    /// the pause feature treats its own duration.
    private func shiftIdleClocks(by delta: TimeInterval) {
        guard delta > 0 else { return }
        for (bundleID, date) in Array(lastActiveDates) {
            lastActiveDates[bundleID] = date.addingTimeInterval(delta)
        }
        for (bundleID, deadline) in Array(graceDeadlines) {
            graceDeadlines[bundleID] = deadline.addingTimeInterval(delta)
        }
    }

    // MARK: - Control

    func openSettings() {
        openSettingsAction?()
    }

    func openSettings(_ tab: SettingsTab) {
        openSettingsTabAction?(tab)
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

    /// Cancels every pending quit at once, for the inline panel in the popover.
    func keepAllPending() {
        // Snapshot the keys: keepRunning mutates graceDeadlines.
        for bundleID in Array(graceDeadlines.keys) {
            keepRunning(bundleID: bundleID)
        }
        pendingQuits.removeAll()
    }

    /// Force quits an app immediately. Used when a normal quit request was
    /// ignored, or from the row's context menu.
    func forceQuitNow(_ app: AppInfo) {
        cancelPendingQuit(app.bundleID)
        let handled = quitManager.forceQuit(app)
        quitRequests[app.bundleID] = Date()
        unresponsiveApps.remove(app.bundleID)
        if handled {
            record(app, reason: .manual)
            logger.debug("Force quit \(app.name, privacy: .public)")
        }
    }

    // MARK: - Background sweep

    /// Stops every blacklisted background item in one go: menu bar apps are asked
    /// to quit, CLI processes get SIGTERM then SIGKILL.
    ///
    /// Background items never participate in the idle countdown, so this is the
    /// only path that closes them. Everything not on the blacklist is left alone.
    /// With `skipActiveBackgroundItems` on, items that are visibly working are
    /// reported as skipped instead of being stopped.
    /// Progress and the final tally are published through
    /// `isBackgroundSweepInFlight` and `lastBackgroundCleanup`.
    func closeBlacklistedBackgroundApps() {
        let targets = blacklistedBackgroundItems
        guard !targets.isEmpty else {
            lastBackgroundCleanup = BackgroundCleanupResult(
                date: Date(), quitCount: 0, stubbornCount: 0,
                skippedActiveCount: 0, keptCount: keptBackgroundItems.count
            )
            return
        }

        let skipped = skipActiveBackgroundItems ? targets.filter(\.isActive) : []
        let skippedIDs = Set(skipped.map(\.id))
        let toStop = targets.filter { !skippedIDs.contains($0.id) }
        let kept = keptBackgroundItems.count
        isBackgroundSweepInFlight = true

        Task { @MainActor [weak self] in
            var quitCount = 0
            var stubbornCount = 0

            for item in toStop {
                guard let self else { return }
                let stopped: Bool
                switch item {
                case .app(let app):
                    stopped = await self.stopApp(app)
                case .process(let group):
                    stopped = await ProcessScanner.terminate(group)
                }
                if stopped {
                    quitCount += 1
                    self.record(item, reason: .background)
                } else {
                    stubbornCount += 1
                }
            }

            guard let self else { return }
            self.isBackgroundSweepInFlight = false
            self.lastBackgroundCleanup = BackgroundCleanupResult(
                date: Date(), quitCount: quitCount, stubbornCount: stubbornCount,
                skippedActiveCount: skipped.count, keptCount: kept
            )
            self.logger.debug(
                "Background sweep stopped \(quitCount), \(stubbornCount) still running, \(skipped.count) skipped as active"
            )
        }
    }

    /// Asks a menu bar app to quit, then force quits it if it ignores the request.
    private func stopApp(_ app: AppInfo) async -> Bool {
        guard let running = QuitManager.runningApplication(for: app.bundleID) else {
            return true
        }
        quitManager.quit(app)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if running.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(150))
        }

        quitManager.forceQuit(app)
        let forceDeadline = Date().addingTimeInterval(2)
        while Date() < forceDeadline {
            if running.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return running.isTerminated
    }

    // MARK: - Background blacklist

    func isBackgroundBlacklisted(_ target: BackgroundTarget) -> Bool {
        backgroundBlacklist.contains { $0.target == target }
    }

    func setBackgroundBlacklisted(_ isBlacklisted: Bool, target: BackgroundTarget) {
        let name = backgroundItems.first { $0.target == target }?.name
            ?? backgroundBlacklist.first { $0.target == target }?.name
            ?? Self.fallbackName(for: target)
        if isBlacklisted {
            guard !isBackgroundBlacklisted(target) else { return }
            backgroundBlacklist.append(BackgroundEntry(target: target, name: name))
        } else {
            backgroundBlacklist.removeAll { $0.target == target }
        }
    }

    private static func fallbackName(for target: BackgroundTarget) -> String {
        switch target {
        case .app(let bundleID): return bundleID
        case .process(let path): return (path as NSString).lastPathComponent
        }
    }

    /// Fills in real names for entries saved before the name was known, so the
    /// "not running" section does not show raw bundle IDs or paths.
    private func resolveBackgroundNames() {
        // Writing to `backgroundBlacklist` re-enters this through its observer.
        guard !isResolvingBackgroundNames else { return }
        isResolvingBackgroundNames = true
        defer { isResolvingBackgroundNames = false }

        let names = Dictionary(
            backgroundItems.map { ($0.target, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        var updated = backgroundBlacklist
        for (index, entry) in updated.enumerated() {
            guard entry.name == Self.fallbackName(for: entry.target) else { continue }
            guard let name = names[entry.target] else { continue }
            updated[index] = BackgroundEntry(target: entry.target, name: name)
        }
        if updated != backgroundBlacklist {
            backgroundBlacklist = updated
        }
    }

    private func saveBackgroundBlacklist() {
        guard let data = try? JSONEncoder().encode(backgroundBlacklist) else { return }
        UserDefaults.standard.set(data, forKey: "backgroundBlacklist")
    }

    private static func loadBackgroundBlacklist() -> [BackgroundEntry] {
        guard let data = UserDefaults.standard.data(forKey: "backgroundBlacklist") else {
            return []
        }
        // The intermediate build stored entries with a bare `bundleID`, before
        // CLI processes were supported. Decode those instead of dropping them.
        if let entries = try? JSONDecoder().decode([BackgroundEntry].self, from: data) {
            return entries
        }
        if let legacy = try? JSONDecoder().decode([LegacyBackgroundEntry].self, from: data) {
            return legacy.map {
                BackgroundEntry(target: .app(bundleID: $0.bundleID), name: $0.name)
            }
        }
        return []
    }

    private struct LegacyBackgroundEntry: Codable {
        let bundleID: String
        let name: String
    }

    func startMonitoring() {
        monitor.start()
        rebuildTimers()
    }

    func stopMonitoring() {
        monitor.stop()
        tickTimer?.invalidate()
        tickTimer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
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
                for (bundleID, date) in Array(lastActiveDates) {
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
        recordQuit(name: app.name, bundleID: app.bundleID, reason: reason)
    }

    private func record(_ item: BackgroundItem, reason: QuitReason) {
        switch item {
        case .app(let app):
            recordQuit(name: app.name, bundleID: app.bundleID, reason: reason)
        case .process(let group):
            recordQuit(name: group.name, bundleID: group.displayPath, reason: reason)
        }
    }

    private func recordQuit(name: String, bundleID: String, reason: QuitReason) {
        history.insert(
            QuitEvent(date: Date(), appName: name, bundleID: bundleID, reason: reason),
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
        // Restarting the timer deliberately is not the same as the process being
        // suspended, so the next tick must not treat the gap as sleep.
        lastTickDate = nil
        if !isAutoQuitEnabled {
            remainingSeconds = [:]
        }
        // The timer also watches for ignored quit requests, which matters even
        // with auto quit off (manual quits can be ignored too), so it always runs.
        tickTimer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        let now = Date()

        // The timer can be suspended without a wake notification (fast user
        // switching, a stalled run loop). Treat any suspiciously long gap as
        // time that should not count towards idleness. While paused this is
        // already handled by `resumePause`, so skip it to avoid shifting twice.
        if pausedUntil == nil, let last = lastTickDate {
            let gap = now.timeIntervalSince(last)
            if gap > Self.maximumTickGap {
                shiftIdleClocks(by: gap)
                lastAudioRefresh = .distantPast
                logger.debug("Tick gap of \(gap, privacy: .public)s shifted idleness clocks")
            }
        }
        lastTickDate = now
        updateSystemIdle()

        if let until = pausedUntil {
            if until > now {
                pauseRemaining = until.timeIntervalSince(now)
                remainingSeconds = [:]
                return
            }
            resumePause()
        }
        pauseRemaining = 0

        // Outside quiet hours the countdown is frozen: apps should not bank up
        // idleness during the window and all quit the moment it closes.
        let inQuietHours = quietHoursEnabled && Self.isQuietHour(
            date: now,
            startHour: quietStartHour,
            endHour: quietEndHour,
            weekdaysOnly: quietWeekdaysOnly
        )
        if isQuietPeriod != inQuietHours {
            isQuietPeriod = inQuietHours
            logger.debug("Quiet hours active: \(inQuietHours, privacy: .public)")
        }
        if inQuietHours {
            // Keep every clock fresh so no app is overdue when the window ends.
            for app in runningApps where app.bundleID != SystemApps.selfBundleID {
                lastActiveDates[app.bundleID] = now
            }
            if !graceDeadlines.isEmpty { cancelAllPendingQuits() }
            remainingSeconds = [:]
            updateUnresponsiveApps(now: now)
            return
        }

        // With auto quit off the countdown does not run, but an ignored manual
        // quit must still surface so the user can force it.
        if !isAutoQuitEnabled {
            remainingSeconds = [:]
            updateUnresponsiveApps(now: now)
            return
        }

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

            if skipAudioApps, audioBundleIDs.contains(bundleID) {
                // Playing audio or in a call: keep the clock fresh and never quit.
                lastActiveDates[bundleID] = now
                dropPending(bundleID)
                continue
            }

            if bundleID == foregroundBundleID {
                if isUserAwayFromMac {
                    // Nobody is at the Mac, so the frontmost app is idle too.
                    if lastActiveDates[bundleID] == nil {
                        lastActiveDates[bundleID] = now
                    }
                } else {
                    lastActiveDates[bundleID] = now
                    dropPending(bundleID)
                    continue
                }
            } else if lastActiveDates[bundleID] == nil {
                // Track apps we discover after launch (including ones that were
                // already running in the background) so the countdown starts.
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
        updateUnresponsiveApps(now: now)
        remainingSeconds = updated
    }

    /// An app that is still alive a while after being asked to quit is not going
    /// to close on its own; expose that so the user can force it.
    private func updateUnresponsiveApps(now: Date) {
        let running = Set(runningApps.map(\.bundleID))
        unresponsiveApps = Set(quitRequests.compactMap { bundleID, requestedAt in
            guard running.contains(bundleID) else { return nil }
            return now.timeIntervalSince(requestedAt) >= Self.unresponsiveTimeout ? bundleID : nil
        })
    }

    // MARK: - System idle

    private func updateSystemIdle() {
        let anyEvent = CGEventType(rawValue: ~0)!
        systemIdleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    /// True when the option is on and the user has not touched the Mac for long
    /// enough that even the frontmost app should count as idle.
    private var isUserAwayFromMac: Bool {
        guard useSystemIdle else { return false }
        return systemIdleSeconds >= systemIdleMinutes * 60
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
        for bundleID in Array(graceDeadlines.keys) {
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
