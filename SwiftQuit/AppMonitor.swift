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

final class AppMonitor {
    private let onUpdate: ([AppInfo], String) -> Void
    private var timer: Timer?

    init(onUpdate: @escaping ([AppInfo], String) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
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
        let apps = NSWorkspace.shared.runningApplications
            .filter { ($0.bundleIdentifier ?? "").isEmpty == false && $0.activationPolicy == .regular }
            .map { AppInfo(runningApp: $0) }
        let fg = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        onUpdate(apps, fg)
    }
}
