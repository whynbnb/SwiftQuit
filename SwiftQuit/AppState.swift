import SwiftUI
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

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
        didSet { LaunchAtLoginManager.shared.setEnabled(launchAtLogin) }
    }
    @Published var foregroundBundleID: String = "" {
        didSet { touchForeground() }
    }
    @Published var remainingSeconds: [String: Double] = [:]

    private var monitor: AppMonitor!
    private var quitManager: QuitManager!
    private var lastActiveDates: [String: Date] = [:]
    private var tickTimer: Timer?
    private var prevForeground: String = ""

    private init() {
        idleMinutes = UserDefaults.standard.object(forKey: "idleMinutes") as? Double ?? 60
        isAutoQuitEnabled = UserDefaults.standard.object(forKey: "isAutoQuitEnabled") as? Bool ?? true
        excludedBundleIDs = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])

        monitor = AppMonitor { [weak self] apps, fg in
            self?.runningApps = apps
            self?.foregroundBundleID = fg
        }
        quitManager = QuitManager()
        loadExcluded()
    }

    func quitNow(_ app: AppInfo) {
        quitManager.quit(app)
    }

    func startMonitoring() {
        monitor.start()
        rebuildTimers()
    }

    private func touchForeground() {
        guard foregroundBundleID != prevForeground else { return }
        if !prevForeground.isEmpty {
            lastActiveDates[prevForeground] = Date()
        }
        lastActiveDates[foregroundBundleID] = Date()
        prevForeground = foregroundBundleID
    }

    private func rebuildTimers() {
        tickTimer?.invalidate()
        guard isAutoQuitEnabled else {
            remainingSeconds = [:]
            return
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let threshold = idleMinutes * 60
        let now = Date()
        var updated: [String: Double] = [:]

        for app in runningApps {
            guard !excludedBundleIDs.contains(app.bundleID) else { continue }
            guard app.bundleID != Bundle.main.bundleIdentifier else { continue }
            guard app.bundleID != "com.apple.finder" else { continue }

            if app.bundleID == foregroundBundleID {
                lastActiveDates[app.bundleID] = now
                continue
            }

            let lastActive = lastActiveDates[app.bundleID] ?? now
            let elapsed = now.timeIntervalSince(lastActive)
            let remaining = max(0, threshold - elapsed)

            if remaining <= 0 {
                quitManager.quit(app)
                updated[app.bundleID] = 0
            } else {
                updated[app.bundleID] = remaining
            }
        }
        remainingSeconds = updated
    }

    private func saveExcluded() {
        UserDefaults.standard.set(Array(excludedBundleIDs), forKey: "excludedBundleIDs")
    }

    private func loadExcluded() {
        if let arr = UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") {
            excludedBundleIDs = Set(arr)
        }
    }
}
