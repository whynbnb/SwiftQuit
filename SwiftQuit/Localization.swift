import Foundation

/// Language selected by the user. `.system` follows the macOS preferred language.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    /// The concrete language used for rendering (never `.system`).
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .chinese : .english
    }
}

/// All user-facing strings, resolved for a concrete language.
struct Strings: Sendable {
    let language: AppLanguage

    init(language: AppLanguage) {
        self.language = language.resolved == .chinese ? .chinese : .english
    }

    private func pick(_ english: String, _ chinese: String) -> String {
        language == .chinese ? chinese : english
    }

    // MARK: - Popover

    var autoQuit: String { pick("Auto Quit", "自动退出") }
    var launchAtLogin: String { pick("Launch at Login", "开机自启") }
    var settings: String { pick("Settings…", "设置…") }
    var settingsTitle: String { pick("Settings", "设置") }
    var quitApp: String { pick("Quit SwiftQuit", "退出 SwiftQuit") }
    var quit: String { pick("Quit", "退出") }
    var quitHint: String { pick("Quit this app", "退出该应用") }
    var closeWindows: String { pick("Close", "关闭") }
    var closeWindowsHint: String { pick("Close all Finder windows", "关闭访达的所有窗口") }
    var quitting: String { pick("Quitting…", "正在退出…") }
    var includeInAutoQuit: String { pick("Include in auto-quit", "参与自动退出") }
    var includeInAutoQuitHint: String { pick("Uncheck to keep this app running", "取消勾选可让该应用保持运行") }

    // MARK: - Pause

    var pauseAutoQuit: String { pick("Pause Auto Quit", "暂停自动退出") }
    var pauseOneHour: String { pick("Pause for 1 Hour", "暂停 1 小时") }
    var pauseUntilTomorrow: String { pick("Pause Until Tomorrow", "暂停到今天结束") }
    var resumeNow: String { pick("Resume", "恢复") }

    func pausedUntilLabel(time: String) -> String {
        pick("Paused until \(time)", "已暂停至 \(time)")
    }

    func pauseBanner(remaining: String) -> String {
        pick("Auto quit paused · \(remaining) left", "自动退出已暂停 · 剩余 \(remaining)")
    }

    func pauseRemaining(seconds: TimeInterval) -> String {
        let total = max(1, Int(seconds.rounded()))
        if total < 60 {
            return language == .chinese ? "\(total) 秒" : "\(total) s"
        }
        let minutes = Int((Double(total) / 60).rounded(.up))
        return duration(minutes: minutes)
    }

    // MARK: - Grace period

    var gracePeriod: String { pick("Grace period", "退出前等待") }

    func graceOption(seconds: Int) -> String {
        if seconds == 0 { return pick("Immediate", "立即") }
        if seconds < 60 { return pick("\(seconds) seconds", "\(seconds) 秒") }
        return pick("\(seconds / 60) minute", "\(seconds / 60) 分钟")
    }

    func quittingIn(seconds: Int) -> String {
        pick("Quitting in \(seconds)s", "\(seconds) 秒后退出")
    }

    // MARK: - Audio

    var skipAudioApps: String { pick("Don't quit apps playing audio", "播放声音或通话时不退出") }

    // MARK: - Settings

    var general: String { pick("General", "通用") }
    var appsTab: String { pick("Apps", "应用") }
    var historyTab: String { pick("History", "记录") }
    var enableAutoQuit: String { pick("Enable auto quit", "启用自动退出") }
    var idleThreshold: String { pick("Idle threshold", "空闲阈值") }
    var languageTitle: String { pick("Language", "语言") }
    var followSystem: String { pick("Follow System", "跟随系统") }
    var languageNote: String { pick("Applied immediately.", "立即生效。") }
    var loginItemError: String {
        pick(
            "Could not update the login item. Move SwiftQuit to /Applications and try again.",
            "无法更新登录项。请将 SwiftQuit 移到「应用程序」文件夹后重试。"
        )
    }
    var appsDescription: String {
        pick(
            "Checked apps quit automatically after being idle in the background. Uncheck an app to keep it running. Finder can't quit, so its windows are closed instead.",
            "勾选的应用在后台空闲一段时间后会自动退出；取消勾选即可让它一直保持运行。Finder 无法退出，将改为关闭其打开的窗口。"
        )
    }
    func appsSummary(included: Int, total: Int) -> String {
        pick(
            "\(included) of \(total) apps auto-managed",
            "自动管理 \(included)/\(total) 个应用"
        )
    }
    var showFinder: String { pick("Show Finder", "显示 Finder") }
    var autoQuitStatus: String { pick("Quits when idle", "空闲后自动退出") }
    var closeWindowsStatus: String { pick("Closes windows when idle", "空闲后关闭窗口") }
    var keepRunningStatus: String { pick("Kept running", "保持运行") }
    var noRunningApps: String { pick("No running apps", "没有运行中的应用") }

    // MARK: - Per-app threshold

    var useGlobalShort: String { pick("Global", "全局") }

    func useGlobalThreshold(duration: String) -> String {
        pick("Use global (\(duration))", "跟随全局（\(duration)）")
    }

    // MARK: - History

    var historyDescription: String {
        pick(
            "The most recent automatic and manual quits.",
            "最近发生的自动退出与手动退出记录。"
        )
    }
    var historyEmpty: String { pick("No quits yet", "还没有退出记录") }
    var historyClear: String { pick("Clear", "清空") }

    func reasonLabel(_ reason: QuitReason) -> String {
        switch reason {
        case .idle: return pick("Idle", "空闲")
        case .manual: return pick("Manual", "手动")
        case .windows: return pick("Windows", "关闭窗口")
        case .background: return pick("Background", "后台清理")
        }
    }

    // MARK: - Background items

    var backgroundTab: String { pick("Background", "后台") }
    var backgroundSection: String { pick("Background", "后台") }
    var closeBackgroundApps: String { pick("Close Background Items", "关闭后台项目") }
    var closeBackgroundAppsHint: String {
        pick(
            "Stop every blacklisted background item now; whitelisted ones keep running.",
            "立即关闭黑名单里的所有后台项目，白名单内的保持运行。"
        )
    }
    var backgroundDescription: String {
        pick(
            "Menu bar agents, command line tools and daemons never follow the idle countdown. Turn an item on to blacklist it, then use the button to stop them all at once. Everything else keeps running.",
            "菜单栏应用、命令行工具和守护进程都不参与空闲倒计时。打开某个项目即加入黑名单，然后点按钮一次性全部关闭；其余项目保持运行。"
        )
    }
    var backgroundMenuBarSection: String { pick("Menu Bar Apps", "菜单栏应用") }
    var backgroundProcessSection: String { pick("Command Line Processes", "命令行进程") }
    var backgroundNotRunning: String { pick("Not running", "未运行") }
    var backgroundAncestorSection: String { pick("Currently excluded", "当前排除") }
    var backgroundAncestorStatus: String { pick("Launching SwiftQuit", "正在托管 SwiftQuit") }
    var backgroundAncestorNote: String {
        pick(
            "SwiftQuit is running inside these processes, so stopping them would close the session that launched it. They are listed and stoppable again when SwiftQuit runs on its own.",
            "SwiftQuit 目前运行在这些进程内部，关闭它们会连带关闭启动 SwiftQuit 的会话。单独运行 SwiftQuit 时，它们会正常列出并可清理。"
        )
    }
    var backgroundEmpty: String { pick("No background items running", "没有正在运行的后台项目") }
    var backgroundBlacklisted: String { pick("Blacklisted", "黑名单") }
    var backgroundKept: String { pick("Kept running", "白名单，保留") }
    var closeNow: String { pick("Close Now", "立即关闭") }
    var removeFromList: String { pick("Remove", "移出") }
    var removeFromListHint: String {
        pick("Keep this item running during clean-up", "清理时保留该项目，不关闭")
    }
    var manageEllipsis: String { pick("Manage…", "管理…") }
    var backgroundPopoverEmpty: String {
        pick("Nothing blacklisted yet", "还没有加入黑名单的后台项目")
    }

    func backgroundAllClosed(count: Int) -> String {
        pick(
            "\(count) blacklisted item\(count == 1 ? "" : "s") not running",
            "黑名单中的 \(count) 个项目当前未运行"
        )
    }
    var backgroundIntro: String {
        pick(
            "Menu bar agents and command line processes are excluded from the idle countdown.",
            "菜单栏应用与命令行进程都不参与上面的空闲倒计时。"
        )
    }

    func backgroundSummary(blacklisted: Int, kept: Int) -> String {
        pick(
            "\(blacklisted) to close · \(kept) kept",
            "黑名单 \(blacklisted) 个 · 保留 \(kept) 个"
        )
    }

    func backgroundSweepResult(quit: Int, kept: Int) -> String {
        if quit == 0 {
            return pick("Nothing to close", "没有需要关闭的应用")
        }
        return pick(
            "Closed \(quit) app\(quit == 1 ? "" : "s"), kept \(kept)",
            "已关闭 \(quit) 个，保留 \(kept) 个"
        )
    }

    func backgroundSweepWarning(stubborn: Int) -> String {
        pick(
            "\(stubborn) app\(stubborn == 1 ? "" : "s") did not quit",
            "\(stubborn) 个应用未退出"
        )
    }

    // MARK: - Notifications

    func notificationTitle(app: String) -> String {
        pick("\(app) is idle", "\(app) 已空闲")
    }
    var notificationTitleCloseWindows: String { pick("Finder windows are idle", "访达窗口已空闲") }

    func notificationBody(seconds: Int) -> String {
        pick(
            "Quitting in \(seconds)s. Choose Keep Running to cancel.",
            "\(seconds) 秒后退出，选择「保持运行」可取消。"
        )
    }

    func nextQuitTooltip(app: String, duration: String, closesWindows: Bool) -> String {
        if closesWindows {
            return pick("\(app) windows close in \(duration)", "\(app) 将在 \(duration) 后关闭窗口")
        }
        return pick("\(app) quits in \(duration)", "\(app) 将在 \(duration) 后退出")
    }

    func notificationBodyClosingWindows(seconds: Int) -> String {
        pick(
            "Closing in \(seconds)s. Choose Keep Running to cancel.",
            "\(seconds) 秒后关闭窗口，选择「保持运行」可取消。"
        )
    }

    var keepRunning: String { pick("Keep Running", "保持运行") }

    // MARK: - Formatting

    func duration(minutes: Int) -> String {
        if minutes >= 60 && minutes % 60 == 0 {
            return language == .chinese ? "\(minutes / 60) 小时" : "\(minutes / 60) h"
        }
        return language == .chinese ? "\(minutes) 分钟" : "\(minutes) min"
    }

    func countdown(minutes: Int, seconds: Int) -> String {
        if language == .chinese {
            return minutes > 0 ? "\(minutes)分\(seconds)秒" : "\(seconds)秒"
        }
        return minutes > 0 ? "\(minutes)m\(seconds)s" : "\(seconds)s"
    }
}
