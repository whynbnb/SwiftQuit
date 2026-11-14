import SwiftUI
import Combine

@main
struct SwiftQuitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    let popover = NSPopover()
    var statusItem: NSStatusItem!
    private var settingsWindowController: NSWindowController?
    private var settingsTabController: NSTabViewController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView().environmentObject(state))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make(paused: state.isPaused)
            button.imagePosition = .imageOnly
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        state.openSettingsAction = { [weak self] in
            self?.showSettings()
        }

        state.$pausedUntil
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateStatusIcon()
                }
            }
            .store(in: &cancellables)

        state.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.localizeSettings()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification, object: nil
        )

        state.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stopMonitoring()
    }

    // MARK: - Status item

    private func updateStatusIcon() {
        statusItem.button?.image = MenuBarIcon.make(paused: state.isPaused)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            if let window = popover.contentViewController?.view.window {
                window.makeKey()
                window.acceptsMouseMovedEvents = true
            }
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard popover.isShown else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.popover.isShown else { return }
            if NSApp.keyWindow == nil || NSApp.keyWindow?.level == .normal {
                let popoverWindow = self.popover.contentViewController?.view.window
                if NSApp.keyWindow !== popoverWindow {
                    self.popover.performClose(nil)
                }
            }
        }
    }

    // MARK: - Status menu

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let strings = state.strings
        let menu = NSMenu()

        if state.isPaused {
            menu.addItem(menuItem(strings.resumeNow, action: #selector(menuResume)))
            if let until = state.pausedUntil {
                let info = NSMenuItem(
                    title: strings.pausedUntilLabel(time: until.formatted(date: .omitted, time: .shortened)),
                    action: nil,
                    keyEquivalent: ""
                )
                info.isEnabled = false
                menu.addItem(info)
            }
        } else {
            menu.addItem(menuItem(strings.pauseOneHour, action: #selector(menuPauseOneHour)))
            menu.addItem(menuItem(strings.pauseUntilTomorrow, action: #selector(menuPauseUntilTomorrow)))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem(strings.settings, action: #selector(menuOpenSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem(strings.quitApp, action: #selector(menuQuitApp)))

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuPauseOneHour() {
        state.pauseForOneHour()
    }

    @objc private func menuPauseUntilTomorrow() {
        state.pauseUntilTomorrow()
    }

    @objc private func menuResume() {
        state.resumePause()
    }

    @objc private func menuOpenSettings() {
        showSettings()
    }

    @objc private func menuQuitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Settings window

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindowController == nil {
            createSettingsWindow()
        }
        localizeSettings()
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func createSettingsWindow() {
        let tabController = NSTabViewController()
        tabController.tabStyle = .toolbar

        let generalHosting = NSHostingController(rootView: GeneralSettingsView().environmentObject(state))
        generalHosting.title = state.strings.settingsTitle
        let general = NSTabViewItem(viewController: generalHosting)
        general.label = state.strings.general
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)

        let appsHosting = NSHostingController(rootView: AppsSettingsView().environmentObject(state))
        appsHosting.title = state.strings.settingsTitle
        let apps = NSTabViewItem(viewController: appsHosting)
        apps.label = state.strings.appsTab
        apps.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)

        let historyHosting = NSHostingController(rootView: HistoryView().environmentObject(state))
        historyHosting.title = state.strings.settingsTitle
        let history = NSTabViewItem(viewController: historyHosting)
        history.label = state.strings.historyTab
        history.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)

        tabController.addTabViewItem(general)
        tabController.addTabViewItem(apps)
        tabController.addTabViewItem(history)
        settingsTabController = tabController

        let window = NSWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.title = state.strings.settingsTitle
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 470))
        window.minSize = NSSize(width: 560, height: 470)
        window.center()

        settingsWindowController = NSWindowController(window: window)
    }

    private func localizeSettings() {
        settingsWindowController?.window?.title = state.strings.settingsTitle

        guard let items = settingsTabController?.tabViewItems, items.count == 3 else { return }
        for (index, label) in [state.strings.general, state.strings.appsTab, state.strings.historyTab].enumerated() {
            items[index].label = label
            items[index].viewController?.title = state.strings.settingsTitle
        }
    }
}
