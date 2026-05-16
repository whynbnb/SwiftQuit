import AppKit

final class QuitManager {
    func quit(_ app: AppInfo) {
        let running = NSWorkspace.shared.runningApplications
        guard let target = running.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        target.terminate()
    }

    func forceQuit(_ app: AppInfo) {
        let running = NSWorkspace.shared.runningApplications
        guard let target = running.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        target.forceTerminate()
    }
}
