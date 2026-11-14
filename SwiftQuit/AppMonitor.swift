import AppKit

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
    private var timer: Timer?

    init(onUpdate: @escaping @MainActor ([AppInfo], String) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
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
