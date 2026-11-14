import Foundation
import ServiceManagement
import OSLog

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    /// `true` when the app is registered, including the pending-user-approval state.
    var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        default:
            return false
        }
    }

    /// - Returns: `true` when `SMAppService` reports the requested state.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger(subsystem: "com.swiftquit.SwiftQuit", category: "LaunchAtLogin")
                .error("\(enabled ? "register" : "unregister", privacy: .public) failed: \(error, privacy: .public)")
            return false
        }
        return isEnabled == enabled
    }
}
