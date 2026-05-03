import AppKit
import MacFanCore
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let store: FanStateStore
    private let loginItemManager: LoginItemManager
    private var timer: Timer?

    init(store: FanStateStore, loginItemManager: LoginItemManager) {
        self.store = store
        self.loginItemManager = loginItemManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        statusItem.button?.title = "--°"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            store: store,
            loginItemManager: loginItemManager,
            onQuit: { [weak store] in
                Task { @MainActor in
                    await store?.prepareForQuit()
                    NSApp.terminate(nil)
                }
            }
        ))

        startClosedStateTimer()
    }

    private func startClosedStateTimer() {
        timer?.invalidate()
        Task { await refreshStatusTitle() }
        timer = Timer.scheduledTimer(withTimeInterval: PerformancePolicy.closedPopoverTemperatureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatusTitle()
            }
        }
    }

    private func startOpenStateTimer() {
        timer?.invalidate()
        Task { await refreshStatusTitle() }
        timer = Timer.scheduledTimer(withTimeInterval: PerformancePolicy.openPopoverRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatusTitle()
            }
        }
    }

    private func refreshStatusTitle() async {
        await store.refreshSnapshot()
        if let temperature = store.snapshot.temperatureCelsius {
            statusItem.button?.title = "\(temperature)°"
        } else {
            statusItem.button?.title = "--°"
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            startOpenStateTimer()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        startClosedStateTimer()
    }
}
