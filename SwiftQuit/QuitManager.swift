import AppKit
import OSLog

@MainActor
final class QuitManager {
    private let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "QuitManager")

    /// Asks the app to quit normally (it may show a save dialog). Returns `true` if the request was delivered.
    ///
    /// Finder cannot be terminated, so its open windows are closed instead.
    @discardableResult
    func quit(_ app: AppInfo) -> Bool {
        if app.bundleID == SystemApps.finderBundleID {
            return closeFinderWindows()
        }
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

    /// Force kills the app without giving it a chance to save. Finder is handled like `quit(_:)`.
    @discardableResult
    func forceQuit(_ app: AppInfo) -> Bool {
        if app.bundleID == SystemApps.finderBundleID {
            return closeFinderWindows()
        }
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

    /// Closes every open Finder window. Requires Automation access to Finder the first time.
    @discardableResult
    func closeFinderWindows() -> Bool {
        guard let script = NSAppleScript(source: "tell application \"Finder\" to close every window") else {
            logger.error("Could not create the Finder window script")
            return false
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            logger.error("Closing Finder windows failed: \(String(describing: error), privacy: .public)")
            return false
        }
        return true
    }

    /// The running process for a bundle ID, if it is still alive.
    static func runningApplication(for bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    private func runningApplication(for app: AppInfo) -> NSRunningApplication? {
        Self.runningApplication(for: app.bundleID)
    }
}
