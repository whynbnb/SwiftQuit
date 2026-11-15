import AppKit
import OSLog

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleID: String
    let icon: NSImage?

    init(runningApp: NSRunningApplication) {
        self.id = runningApp.bundleIdentifier ?? UUID().uuidString
        self.name = runningApp.localizedName ?? "Unknown"
        self.bundleID = runningApp.bundleIdentifier ?? ""
        self.icon = runningApp.icon
    }
}

/// Bundle IDs that need special handling rather than plain `terminate()`.
enum SystemApps {
    static let selfBundleID = Bundle.main.bundleIdentifier ?? "com.swiftquit.SwiftQuit"
    static let finderBundleID = "com.apple.finder"

    /// Whether a process is a user-installed background app (menu bar utility)
    /// that can be listed in the manual clean-up tab. System agents, login items
    /// and helpers nested inside another app bundle are excluded.
    static func isBackgroundCandidate(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .accessory else { return false }
        guard let bundleID = app.bundleIdentifier, !bundleID.isEmpty else { return false }
        guard bundleID != selfBundleID else { return false }
        guard !bundleID.hasPrefix("com.apple.") else { return false }
        guard let url = app.bundleURL, url.pathExtension == "app" else { return false }
        // Skip helpers that live inside another app bundle (login items, XPC services).
        guard !url.path.contains(".app/Contents/") else { return false }
        return isUserApplicationPath(url.path)
    }

    /// Apps installed in the standard Applications folders. Everything else
    /// (`/System`, `/usr/libexec`, `~/Library`, `~/.local`) is treated as a
    /// system service or an internal helper and stays out of the list.
    static func isUserApplicationPath(_ path: String) -> Bool {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(homeApplications + "/")
    }
}

@MainActor
final class AppMonitor {
    private let onUpdate: @MainActor ([AppInfo], [AppInfo], [BackgroundProcess], [BackgroundProcess], String) -> Void
    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "AppMonitor")
    private var timer: Timer?
    private var isRunning = false

    init(onUpdate: @escaping @MainActor ([AppInfo], [AppInfo], [BackgroundProcess], [BackgroundProcess], String) -> Void) {
        self.onUpdate = onUpdate
    }

    isolated deinit {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.debug("Stopped monitoring running applications")
    }

    @objc private func refresh() {
        var seen = Set<String>()
        var backgroundSeen = Set<String>()
        var apps: [AppInfo] = []
        var backgroundApps: [AppInfo] = []

        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, !bid.isEmpty else { continue }
            guard bid != SystemApps.selfBundleID else { continue }

            if SystemApps.isBackgroundCandidate(app) {
                guard backgroundSeen.insert(bid).inserted else { continue }
                backgroundApps.append(AppInfo(runningApp: app))
                continue
            }

            guard app.activationPolicy == .regular else { continue }
            guard app.localizedName != nil || app.icon != nil else { continue }
            guard seen.insert(bid).inserted else { continue }
            apps.append(AppInfo(runningApp: app))
        }

        backgroundApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let fg = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        let scan = ProcessScanner.scan()
        onUpdate(apps, backgroundApps, scan.groups, scan.ancestorGroups, fg)
    }
}
