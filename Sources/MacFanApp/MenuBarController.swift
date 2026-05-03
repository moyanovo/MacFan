import AppKit
import MacFanCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let store: FanStateStore
    private let menuController: NativeStatusMenuController
    private var timer: Timer?
    private var isRefreshing = false

    init(store: FanStateStore, loginItemManager: LoginItemManager) {
        self.store = store
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
            self?.startOpenStateTimer(refreshNow: false)
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
        let timer = Timer(timeInterval: PerformancePolicy.closedMenuTemperatureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatusTitle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func startOpenStateTimer(refreshNow: Bool = true) {
        timer?.invalidate()
        if refreshNow {
            Task { await refreshStatusTitle() }
        }
        let timer = Timer(timeInterval: PerformancePolicy.openMenuRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatusTitle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refreshStatusTitle() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await store.refreshSnapshot()
        if let temperature = store.snapshot.temperatureCelsius {
            statusItem.button?.title = "\(temperature)°"
        } else {
            statusItem.button?.title = "--°"
        }
    }
}
