import AppKit
import UserNotifications
import OSLog

/// Shows a "quitting soon" notification before an app is closed automatically,
/// with a Keep Running action that cancels it.
@MainActor
final class QuitNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated static let keepActionIdentifier = "KEEP_RUNNING"
    nonisolated private static let categoryIdentifier = "IDLE_QUIT"
    private nonisolated static let logger = Logger(subsystem: "com.swiftquit.SwiftQuit", category: "Notifier")

    private let center = UNUserNotificationCenter.current()

    /// Called on the main actor when the user chooses "Keep Running".
    var onKeepRunning: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func configure(strings: Strings) {
        let keep = UNNotificationAction(
            identifier: Self.keepActionIdentifier,
            title: strings.keepRunning,
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [keep],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Self.logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else if !granted {
                Self.logger.info("Notification authorization was not granted")
            }
        }
    }

    func notify(bundleID: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = ["bundleID": bundleID]

        let request = UNNotificationRequest(identifier: bundleID, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Self.logger.error("Could not schedule notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clear(bundleID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [bundleID])
        center.removeDeliveredNotifications(withIdentifiers: [bundleID])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.keepActionIdentifier,
              let bundleID = response.notification.request.content.userInfo["bundleID"] as? String
        else { return }

        await MainActor.run {
            self.onKeepRunning?(bundleID)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
