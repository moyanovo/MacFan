import AppKit
import MacFanCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: FanStateStore
    private let loginItemManager: LoginItemManager
    private let panelController: NativeMenuPanelController
    private var timer: Timer?

    init(store: FanStateStore, loginItemManager: LoginItemManager) {
        self.store = store
        self.loginItemManager = loginItemManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panelController = NativeMenuPanelController(
            store: store,
            loginItemManager: loginItemManager,
            onQuit: { [weak store] in
                Task { @MainActor in
                    await store?.prepareForQuit()
                    NSApp.terminate(nil)
                }
            }
        )
        super.init()
        panelController.closeHandler = { [weak self] in
            self?.statusItem.button?.highlight(false)
            self?.startClosedStateTimer()
        }

        statusItem.button?.title = "--°"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel(_:))

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

    @objc private func togglePanel(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if panelController.isShown {
            panelController.close()
        } else {
            statusItem.button?.highlight(true)
            startOpenStateTimer()
            panelController.show(anchor: button)
        }
    }
}
