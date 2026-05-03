import AppKit
import MacFanCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: FanStateStore
    private let loginItemManager: LoginItemManager
    private let menuController: NativeStatusMenuController
    private var timer: Timer?

    init(store: FanStateStore, loginItemManager: LoginItemManager) {
        self.store = store
        self.loginItemManager = loginItemManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuController = NativeStatusMenuController(
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
        menuController.openHandler = { [weak self] in
            self?.startOpenStateTimer()
        }
        menuController.closeHandler = { [weak self] in
            self?.startClosedStateTimer()
        }

        statusItem.button?.title = "--°"
        statusItem.menu = menuController.menu

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
}
