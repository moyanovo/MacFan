import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager {
    private(set) var hasAskedLaunchAtLogin: Bool
    private(set) var isLaunchAtLoginEnabled: Bool

    private let defaults: UserDefaults
    private let askedKey = "hasAskedLaunchAtLogin"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasAskedLaunchAtLogin = defaults.bool(forKey: askedKey)
        isLaunchAtLoginEnabled = Self.isMainAppRegistered
    }

    func markAsked() {
        hasAskedLaunchAtLogin = true
        defaults.set(true, forKey: askedKey)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isLaunchAtLoginEnabled = enabled
            markAsked()
        } catch {
            isLaunchAtLoginEnabled = false
            markAsked()
        }
    }

    private static var isMainAppRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
