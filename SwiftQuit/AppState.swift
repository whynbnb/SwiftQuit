import SwiftUI
import Combine
import OSLog

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// How long to wait before retrying a quit request that an app appears to have ignored.
    private static let quitRetryInterval: TimeInterval = 30

    @Published var runningApps: [AppInfo] = []
    @Published var excludedBundleIDs: Set<String> = [] {
        didSet { saveExcluded(); rebuildTimers() }
    }
    @Published var idleMinutes: Double = 60 {
        didSet { UserDefaults.standard.set(idleMinutes, forKey: "idleMinutes"); rebuildTimers() }
    }
    @Published var isAutoQuitEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isAutoQuitEnabled, forKey: "isAutoQuitEnabled"); rebuildTimers() }
    }
    @Published var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != LaunchAtLoginManager.shared.isEnabled else { return }
            if LaunchAtLoginManager.shared.setEnabled(launchAtLogin) {
                launchAtLoginError = nil
            } else {
                launchAtLoginError = "Could not update the login item. Move SwiftQuit to /Applications and try again."
                launchAtLogin = LaunchAtLoginManager.shared.isEnabled
            }
        }
    }
    @Published var launchAtLoginError: String?
    @Published var foregroundBundleID: String = "" {
        didSet { touchForeground() }
    }
    @Published var remainingSeconds: [String: Double] = [:]

    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "AppState")
    private var monitor: AppMonitor!
    private var quitManager: QuitManager!
    private var lastActiveDates: [String: Date] = [:]
    private var quitRequests: [String: Date] = [:]
    private var tickTimer: Timer?
    private var prevForeground: String = ""

    private init() {
        idleMinutes = UserDefaults.standard.object(forKey: "idleMinutes") as? Double ?? 60
        isAutoQuitEnabled = UserDefaults.standard.object(forKey: "isAutoQuitEnabled") as? Bool ?? true
        excludedBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        launchAtLogin = LaunchAtLoginManager.shared.isEnabled

        monitor = AppMonitor { @MainActor [weak self] apps, fg in
            self?.runningApps = apps
            self?.foregroundBundleID = fg
        }
        quitManager = QuitManager()
    }

    func quitNow(_ app: AppInfo) {
        quitManager.quit(app)
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

    private func touchForeground() {
        guard foregroundBundleID != prevForeground else { return }
        if !prevForeground.isEmpty {
            lastActiveDates[prevForeground] = Date()
        }
        if !foregroundBundleID.isEmpty {
            // The app is active again, so drop any pending quit for it.
            lastActiveDates[foregroundBundleID] = Date()
            quitRequests[foregroundBundleID] = nil
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
        let threshold = idleMinutes * 60
        let now = Date()
        var updated: [String: Double] = [:]
        var runningBundleIDs = Set<String>()

        for app in runningApps {
            let bundleID = app.bundleID
            runningBundleIDs.insert(bundleID)

            guard bundleID != Bundle.main.bundleIdentifier,
                  bundleID != "com.apple.finder" else { continue }

            if excludedBundleIDs.contains(bundleID) {
                // Keep the clock fresh so re-enabling an app starts a full countdown.
                lastActiveDates[bundleID] = now
                quitRequests[bundleID] = nil
                continue
            }

            if bundleID == foregroundBundleID {
                lastActiveDates[bundleID] = now
                quitRequests[bundleID] = nil
                continue
            }

            // Track apps we discover after launch (including ones that were already
            // running in the background) so the countdown actually starts.
            if lastActiveDates[bundleID] == nil {
                lastActiveDates[bundleID] = now
            }
            let lastActive = lastActiveDates[bundleID] ?? now
            let remaining = max(0, threshold - now.timeIntervalSince(lastActive))

            guard remaining <= 0 else {
                updated[bundleID] = remaining
                continue
            }

            if shouldRequestQuit(bundleID, now: now), quitManager.quit(app) {
                quitRequests[bundleID] = now
                logger.debug("Requested quit for \(app.name, privacy: .public)")
            }
            updated[bundleID] = 0
        }

        // Forget apps that are no longer running, and clear stale quit requests.
        lastActiveDates = lastActiveDates.filter { runningBundleIDs.contains($0.key) }
        quitRequests = quitRequests.filter { runningBundleIDs.contains($0.key) }
        remainingSeconds = updated
    }

    private func shouldRequestQuit(_ bundleID: String, now: Date) -> Bool {
        guard let requestedAt = quitRequests[bundleID] else { return true }
        return now.timeIntervalSince(requestedAt) >= Self.quitRetryInterval
    }

    private func saveExcluded() {
        UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")
    }
}
