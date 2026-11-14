import SwiftUI

@main
struct SwiftQuitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppState.shared)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.shared
    let popover = NSPopover()
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarView().environmentObject(state))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification, object: nil
        )

        state.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stopMonitoring()
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
}
