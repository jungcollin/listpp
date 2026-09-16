import AppKit
import SwiftUI

final class DashboardWindowController: NSObject, NSWindowDelegate {
    private let store: PortStore
    private var window: NSWindow?

    init(store: PortStore) {
        self.store = store
        super.init()
    }

    func show() {
        store.refresh()

        if window == nil {
            window = makeWindow()
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let rootView = DashboardView()
            .environmentObject(store)
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ListPP"
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 760, height: 680))
        window.minSize = NSSize(width: 600, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.titlebarAppearsTransparent = false
        window.backgroundColor = NSColor.windowBackgroundColor
        return window
    }
}
