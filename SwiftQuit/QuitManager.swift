import AppKit
import OSLog

@MainActor
final class QuitManager {
    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "QuitManager")

    /// Asks the app to quit normally (it may show a save dialog). Returns `true` if the request was delivered.
    @discardableResult
    func quit(_ app: AppInfo) -> Bool {
        guard let target = runningApplication(for: app) else {
            logger.debug("App \(app.name, privacy: .public) is no longer running")
            return false
        }
        let sent = target.terminate()
        if !sent {
            logger.error("Failed to request termination of \(app.name, privacy: .public)")
        }
        return sent
    }

    /// Force kills the app without giving it a chance to save.
    @discardableResult
    func forceQuit(_ app: AppInfo) -> Bool {
        guard let target = runningApplication(for: app) else {
            logger.debug("App \(app.name, privacy: .public) is no longer running")
            return false
        }
        let sent = target.forceTerminate()
        if !sent {
            logger.error("Failed to force terminate \(app.name, privacy: .public)")
        }
        return sent
    }

    private func runningApplication(for app: AppInfo) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == app.bundleID }
    }
}
