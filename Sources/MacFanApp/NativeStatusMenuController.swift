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

    private func addHeader() {
        menu.addItem(sectionItem("MacFan"))
        menu.addItem(disabledItem(title: "CPU / SoC", subtitle: store.snapshot.temperatureCelsius.map { "\($0)°" } ?? "--°"))
        menu.addItem(disabledItem(title: "Fan", subtitle: store.snapshot.isControlAvailable ? store.mode.displayName : "Unavailable"))
        menu.addItem(disabledItem(title: "RPM", subtitle: store.snapshot.currentRPM.map { "\($0) RPM" } ?? "—"))
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
        let item = actionItem(
            title: "Manual Linear Control",
            subtitle: "Set an exact fan speed",
            action: #selector(manualTogglePressed),
            symbol: "slider.horizontal.3"
        )
        item.state = store.mode == .manualLinear ? .on : .off
        item.isEnabled = store.snapshot.isControlAvailable
        menu.addItem(item)

        if store.mode == .manualLinear {
            menu.addItem(manualSliderItem())
        }
    }

    private func addLaunchAtLogin() {
        let item = actionItem(
            title: "Launch at Login",
            subtitle: "Show temperature automatically",
            action: #selector(launchAtLoginPressed),
            symbol: "power.circle"
        )
        item.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(item)
    }

    private func modeItem(_ mode: FanMode, title: String, subtitle: String, symbol: String) -> NSMenuItem {
        let item = actionItem(title: title, subtitle: subtitle, action: #selector(modePressed(_:)), symbol: symbol)
        item.representedObject = mode.identifier
        item.state = store.mode == mode ? .on : .off
        item.isEnabled = store.snapshot.isControlAvailable || mode == .systemAuto
        return item
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
        apply(subtitle, to: item)
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

    private func apply(_ subtitle: String?, to item: NSMenuItem) {
        guard let subtitle else { return }
        if #available(macOS 14.4, *) {
            item.subtitle = subtitle
        } else {
            item.title = "\(item.title)  \(subtitle)"
        }
    }

    @objc private func modePressed(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String, let mode = FanMode(identifier: identifier) else { return }
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

    @objc private func manualTogglePressed() {
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

    @objc private func launchAtLoginPressed() {
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
