import AppKit
import MacFanCore

@MainActor private var retainedDelegate: AppDelegate?

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = FanStateStore(client: AppFanControlClient())
        let loginItemManager = LoginItemManager()
        menuBarController = MenuBarController(store: store, loginItemManager: loginItemManager)
    }

}

@main
enum MacFanApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}
