import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            if enabled {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    print("Launch at login register error: \(error)")
                }
            } else {
                do {
                    try SMAppService.mainApp.unregister()
                } catch {
                    print("Launch at login unregister error: \(error)")
                }
            }
        } else {
            SMLoginItemSetEnabled("com.swiftquit.helper" as CFString, enabled)
        }
    }
}
