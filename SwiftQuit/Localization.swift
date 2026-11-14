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

    // MARK: - Settings

    var general: String { pick("General", "通用") }
    var appsTab: String { pick("Apps", "应用") }
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
    func appsSummary(included: Int, total: Int, idle: String) -> String {
        pick(
            "\(included) of \(total) apps auto-managed · idle threshold \(idle)",
            "自动管理 \(included)/\(total) 个应用 · 空闲阈值 \(idle)"
        )
    }
    var showFinder: String { pick("Show Finder", "显示 Finder") }
    var autoQuitStatus: String { pick("Quits when idle", "空闲后自动退出") }
    var closeWindowsStatus: String { pick("Closes windows when idle", "空闲后关闭窗口") }
    var keepRunningStatus: String { pick("Kept running", "保持运行") }
    var noRunningApps: String { pick("No running apps", "没有运行中的应用") }

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
