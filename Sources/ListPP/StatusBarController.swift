import AppKit
import Combine
import SwiftUI

final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: PortStore
    private var cancellables = Set<AnyCancellable>()
    private var dismissalMonitors: [Any] = []

    init(store: PortStore) {
        self.store = store
        super.init()
    }

    func start() {
        configurePopover()
        configureStatusItem()
        updateStatusItemAppearance()

        store.$entries
            .combineLatest(store.$lastUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateStatusItemAppearance()
            }
            .store(in: &cancellables)
    }

    func stop() {
        closePopover()
        cancellables.removeAll()
    }

    func closePopover() {
        popover.performClose(nil)
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 320, height: 220)

        let rootView = MenuBarView()
            .environmentObject(store)
        let hosting = NSHostingController(rootView: rootView)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = [.preferredContentSize]
        }
        popover.contentViewController = hosting
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.refresh()
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            let fitting = view.fittingSize
            popover.contentSize = NSSize(
                width: 320,
                height: min(max(fitting.height, 160), 460)
            )
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.isHighlighted = true
        popover.contentViewController?.view.window?.makeKey()
        startDismissalMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.isHighlighted = false
        stopDismissalMonitors()
    }

    private func startDismissalMonitors() {
        stopDismissalMonitors()

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        } {
            dismissalMonitors.append(global)
        }

        let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleLocalClick(event)
            return event
        }
        dismissalMonitors.append(local)
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard popover.isShown else { return }
        if let popoverWindow = popover.contentViewController?.view.window, event.window === popoverWindow {
            return
        }
        if event.window === statusItem.button?.window {
            return
        }
        closePopover()
    }

    private func stopDismissalMonitors() {
        for monitor in dismissalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dismissalMonitors.removeAll()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        if store.lastUpdated == nil {
            button.title = ""
        } else {
            button.title = "\(store.entries.count)"
        }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.toolTip = "ListPP — \(store.listeningSummary)"

        let symbolCandidates = ["ferry.fill", "ferry"]
        for symbolName in symbolCandidates {
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Listening Ports") {
                image.isTemplate = true
                button.image = image
                return
            }
        }

        button.image = makeFallbackFerryStatusImage()
    }

    private func makeFallbackFerryStatusImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let symbol = "⛴︎"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = symbol.size(withAttributes: attributes)
        let point = NSPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1
        )
        symbol.draw(at: point, withAttributes: attributes)

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
