import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var hasAskedLaunchAtLogin: Bool
    @Published private(set) var isLaunchAtLoginEnabled: Bool

    private let defaults: UserDefaults
    private let askedKey = "hasAskedLaunchAtLogin"
    private let enabledKey = "isLaunchAtLoginEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasAskedLaunchAtLogin = defaults.bool(forKey: askedKey)
        isLaunchAtLoginEnabled = defaults.bool(forKey: enabledKey)
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
            defaults.set(enabled, forKey: enabledKey)
            markAsked()
        } catch {
            isLaunchAtLoginEnabled = false
            defaults.set(false, forKey: enabledKey)
            markAsked()
        }
    }
}
