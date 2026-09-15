import AppKit

@main
struct ListPPApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PortStore()
    private var statusBar: StatusBarController?
    private var dashboard: DashboardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }

        let dashboard = DashboardWindowController(store: store)
        self.dashboard = dashboard
        store.openDashboard = { [weak self, weak dashboard] in
            self?.statusBar?.closePopover()
            dashboard?.show()
        }

        let statusBar = StatusBarController(store: store)
        self.statusBar = statusBar
        statusBar.start()
        store.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        statusBar?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.showDashboard()
        return true
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        return running.contains { $0.processIdentifier != currentPID }
    }
}
