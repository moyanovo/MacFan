import AppKit
import MacFanCore

@MainActor
final class NativeStatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let store: FanStateStore
    private let loginItemManager: LoginItemManager
    private let onQuit: () -> Void
    private var manualRPM: Int?
    private weak var manualValueLabel: NSTextField?
    private weak var temperatureItem: NSMenuItem?
    private weak var fanItem: NSMenuItem?
    private weak var rpmItem: NSMenuItem?

    var openHandler: (() -> Void)?
    var closeHandler: (() -> Void)?

    init(store: FanStateStore, loginItemManager: LoginItemManager, onQuit: @escaping () -> Void) {
        self.store = store
        self.loginItemManager = loginItemManager
        self.onQuit = onQuit
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
        openHandler?()
        Task {
            await store.refreshSnapshot()
            rebuildMenu()
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        closeHandler?()
    }

    func rebuildMenu() {
        menu.removeAllItems()

        addHeader()
        menu.addItem(.separator())
        addModes()
        menu.addItem(.separator())
        addManualControls()
        menu.addItem(.separator())
        addLaunchAtLogin()
        menu.addItem(.separator())
        menu.addItem(actionItem(title: "Quit MacFan", action: #selector(quitPressed), symbol: "power"))
    }

    func refreshFromStore() {
        updateHeaderItems()
    }

    private func addHeader() {
        menu.addItem(sectionItem("MacFan"))
        let temperatureItem = disabledItem(title: "CPU / SoC", subtitle: store.snapshot.temperatureCelsius.map { "\($0)°" } ?? "--°")
        let fanItem = disabledItem(title: "Fan", subtitle: store.snapshot.isControlAvailable ? store.mode.displayName : "Unavailable")
        let rpmItem = disabledItem(title: "RPM", subtitle: store.snapshot.currentRPM.map { "\($0) RPM" } ?? "—")
        self.temperatureItem = temperatureItem
        self.fanItem = fanItem
        self.rpmItem = rpmItem
        menu.addItem(temperatureItem)
        menu.addItem(fanItem)
        menu.addItem(rpmItem)
    }

    private func addModes() {
        menu.addItem(sectionItem("Mode"))
        menu.addItem(modeItem(.systemAuto, title: "System Auto", subtitle: "Use macOS native fan control", symbol: "checkmark.circle"))
        menu.addItem(modeItem(.preset(.silent), title: "Silent", subtitle: "Low noise", symbol: "speaker.wave.1"))
        menu.addItem(modeItem(.preset(.balanced), title: "Balanced", subtitle: "Everyday cooling", symbol: "fan"))
        menu.addItem(modeItem(.preset(.cool), title: "Cool", subtitle: "More airflow", symbol: "snowflake"))
        menu.addItem(modeItem(.preset(.max), title: "Max", subtitle: "Maximum fan speed", symbol: "wind"))
    }

    private func addManualControls() {
        let item = buttonItem(
            title: "Manual Linear Control",
            subtitle: "Set an exact fan speed",
            symbol: "slider.horizontal.3",
            checked: store.mode == .manualLinear,
            enabled: store.snapshot.isControlAvailable,
            identifier: "manualLinearToggle",
            action: #selector(manualTogglePressed(_:))
        )
        menu.addItem(item)

        if store.mode == .manualLinear {
            menu.addItem(manualSliderItem())
        }
    }

    private func addLaunchAtLogin() {
        let item = buttonItem(
            title: "Launch at Login",
            subtitle: "Show temperature automatically",
            symbol: "power.circle",
            checked: loginItemManager.isLaunchAtLoginEnabled,
            enabled: true,
            identifier: "launchAtLogin",
            action: #selector(launchAtLoginPressed(_:))
        )
        menu.addItem(item)
    }

    private func modeItem(_ mode: FanMode, title: String, subtitle: String, symbol: String) -> NSMenuItem {
        buttonItem(
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            checked: store.mode == mode,
            enabled: store.snapshot.isControlAvailable || mode == .systemAuto,
            identifier: mode.identifier,
            action: #selector(modePressed(_:))
        )
    }

    private func manualSliderItem() -> NSMenuItem {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: 48))

        let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(manualSliderChanged(_:)))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.frame = NSRect(x: 18, y: 20, width: 274, height: 20)

        if let range = store.snapshot.range {
            slider.minValue = Double(range.minRPM)
            slider.maxValue = Double(range.maxRPM)
            let rpm = manualRPM ?? store.snapshot.currentRPM ?? range.minRPM
            slider.doubleValue = Double(range.clamped(rpm))
        }

        let valueLabel = NSTextField(labelWithString: "\(Int(slider.doubleValue.rounded())) RPM")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.frame = NSRect(x: 18, y: 4, width: 274, height: 14)
        manualValueLabel = valueLabel

        container.addSubview(slider)
        container.addSubview(valueLabel)

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = store.snapshot.isControlAvailable
        return item
    }

    private func buttonItem(
        title: String,
        subtitle: String?,
        symbol: String?,
        checked: Bool,
        enabled: Bool,
        identifier: String,
        action: Selector
    ) -> NSMenuItem {
        let height: CGFloat = subtitle == nil ? 34 : 46
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: height))
        container.alphaValue = enabled ? 1.0 : 0.42

        let check = NSTextField(labelWithString: checked ? "✓" : "")
        check.font = .systemFont(ofSize: 18, weight: .semibold)
        check.textColor = .labelColor
        check.alignment = .center
        check.frame = NSRect(x: 12, y: (height - 22) / 2, width: 22, height: 22)
        container.addSubview(check)

        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            let imageView = NSImageView(image: image)
            imageView.contentTintColor = .secondaryLabelColor
            imageView.frame = NSRect(x: 44, y: (height - 18) / 2, width: 18, height: 18)
            container.addSubview(imageView)
        }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 76, y: subtitle == nil ? 8 : 22, width: 218, height: 18)
        container.addSubview(titleLabel)

        if let subtitle {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.frame = NSRect(x: 76, y: 7, width: 218, height: 14)
            container.addSubview(subtitleLabel)
        }

        let button = NSButton(frame: container.bounds)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.target = self
        button.action = action
        button.isEnabled = enabled
        button.isBordered = false
        button.title = ""
        button.focusRingType = .none
        button.setButtonType(.momentaryChange)
        container.addSubview(button)

        let item = NSMenuItem()
        item.view = container
        item.isEnabled = enabled
        return item
    }

    private func actionItem(title: String, subtitle: String? = nil, action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = true
        apply(subtitle, to: item)
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }
        return item
    }

    private func disabledItem(title: String, subtitle: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        set(title: title, subtitle: subtitle, on: item)
        return item
    }

    private func sectionItem(_ title: String) -> NSMenuItem {
        let item = disabledItem(title: title)
        let attributed = NSMutableAttributedString(string: title)
        attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: NSRange(location: 0, length: attributed.length))
        attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: 0, length: attributed.length))
        item.attributedTitle = attributed
        return item
    }

    private func updateHeaderItems() {
        if let temperatureItem {
            set(title: "CPU / SoC", subtitle: store.snapshot.temperatureCelsius.map { "\($0)°" } ?? "--°", on: temperatureItem)
        }
        if let fanItem {
            set(title: "Fan", subtitle: store.snapshot.isControlAvailable ? store.mode.displayName : "Unavailable", on: fanItem)
        }
        if let rpmItem {
            set(title: "RPM", subtitle: store.snapshot.currentRPM.map { "\($0) RPM" } ?? "—", on: rpmItem)
        }
    }

    private func set(title: String, subtitle: String?, on item: NSMenuItem) {
        item.title = title
        item.attributedTitle = nil
        apply(subtitle, to: item)
    }

    private func apply(_ subtitle: String?, to item: NSMenuItem) {
        guard let subtitle else { return }
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        } else {
            item.title = "\(item.title)  \(subtitle)"
        }
    }

    @objc private func modePressed(_ sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue, let mode = FanMode(identifier: identifier) else { return }
        Task {
            switch mode {
            case .systemAuto:
                try? await store.returnToSystemAuto()
            case .preset(let preset):
                try? await store.selectPreset(preset)
            case .manualLinear:
                break
            }
            manualRPM = store.snapshot.currentRPM
            await store.refreshSnapshot()
            rebuildMenu()
        }
    }

    @objc private func manualTogglePressed(_ sender: NSButton) {
        Task {
            if store.mode == .manualLinear {
                try? await store.returnToSystemAuto()
            } else {
                let rpm = seedManualRPM()
                manualRPM = rpm
                try? await store.setManualRPM(rpm)
            }
            await store.refreshSnapshot()
            rebuildMenu()
        }
    }

    @objc private func manualSliderChanged(_ sender: NSSlider) {
        let rpm = Int(sender.doubleValue.rounded())
        manualRPM = rpm
        manualValueLabel?.stringValue = "\(rpm) RPM"
        Task {
            try? await store.setManualRPM(rpm)
        }
    }

    @objc private func launchAtLoginPressed(_ sender: NSButton) {
        loginItemManager.setLaunchAtLogin(!loginItemManager.isLaunchAtLoginEnabled)
        rebuildMenu()
    }

    @objc private func quitPressed() {
        onQuit()
    }

    private func seedManualRPM() -> Int {
        if let range = store.snapshot.range {
            return range.clamped(store.snapshot.currentRPM ?? manualRPM ?? range.minRPM)
        }
        return store.snapshot.currentRPM ?? manualRPM ?? 0
    }
}

private extension FanMode {
    var identifier: String {
        switch self {
        case .systemAuto: "systemAuto"
        case .preset(let preset): "preset.\(preset.rawValue)"
        case .manualLinear: "manualLinear"
        }
    }

    init?(identifier: String) {
        if identifier == "systemAuto" {
            self = .systemAuto
        } else if identifier == "manualLinear" {
            self = .manualLinear
        } else if identifier.hasPrefix("preset."),
                  let raw = identifier.split(separator: ".").last,
                  let preset = FanPreset(rawValue: String(raw)) {
            self = .preset(preset)
        } else {
            return nil
        }
    }
}
