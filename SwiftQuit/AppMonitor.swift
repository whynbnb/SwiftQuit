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

@MainActor
final class AppMonitor {
    private let onUpdate: @MainActor ([AppInfo], String) -> Void
    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "AppMonitor")
    private var timer: Timer?
    private var isRunning = false

    init(onUpdate: @escaping @MainActor ([AppInfo], String) -> Void) {
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
        let apps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard let bid = app.bundleIdentifier, !bid.isEmpty else { return false }
                guard app.activationPolicy == .regular else { return false }
                guard app.localizedName != nil || app.icon != nil else { return false }
                return seen.insert(bid).inserted
            }
            .map { AppInfo(runningApp: $0) }
        let fg = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        onUpdate(apps, fg)
    }
}
