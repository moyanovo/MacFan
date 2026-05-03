import AppKit
import MacFanCore

@MainActor private var retainedDelegate: AppDelegate?

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var loginItemManager: LoginItemManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let store = FanStateStore(client: AppFanControlClient())
        let loginItemManager = LoginItemManager()
        self.loginItemManager = loginItemManager
        menuBarController = MenuBarController(store: store, loginItemManager: loginItemManager)
        presentLaunchAtLoginPromptIfNeeded(loginItemManager)
    }

    private func presentLaunchAtLoginPromptIfNeeded(_ manager: LoginItemManager) {
        guard !manager.hasAskedLaunchAtLogin else { return }

        let alert = NSAlert()
        alert.messageText = "Launch MacFan at login?"
        alert.informativeText = "MacFan can start automatically so the menu bar temperature is available after you sign in."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            manager.setLaunchAtLogin(true)
        } else {
            manager.markAsked()
        }
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
