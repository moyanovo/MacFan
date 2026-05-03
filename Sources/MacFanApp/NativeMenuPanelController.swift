import AppKit
import MacFanCore

@MainActor
final class NativeMenuPanelController: NSObject {
    private let store: FanStateStore
    private let loginItemManager: LoginItemManager
    private let onQuit: () -> Void
    private let panel: NativeMenuPanel
    private let rootView = RoundedVisualEffectView()
    private let contentStack = NSStackView()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var manualEnabled = false
    private var manualSlider: NSSlider?
    private var modeButtons: [String: NSButton] = [:]
    private var temperatureValueLabel: NSTextField?
    private var rpmValueLabel: NSTextField?
    private var fanStateLabel: NSTextField?
    private var manualValueLabel: NSTextField?
    private var manualSwitch: NSSwitch?
    private var launchSwitch: NSSwitch?

    var closeHandler: (() -> Void)?

    private let panelSize = NSSize(width: 392, height: 548)

    init(store: FanStateStore, loginItemManager: LoginItemManager, onQuit: @escaping () -> Void) {
        self.store = store
        self.loginItemManager = loginItemManager
        self.onQuit = onQuit
        panel = NativeMenuPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        super.init()
        buildPanel()
    }

    var isShown: Bool { panel.isVisible }

    func toggle(anchor button: NSStatusBarButton) {
        if panel.isVisible {
            close()
        } else {
            show(anchor: button)
        }
    }

    func show(anchor button: NSStatusBarButton) {
        Task { await store.refreshSnapshot(); refreshControls() }
        refreshControls()
        panel.setFrame(panelFrame(anchoredTo: button), display: false)
        panel.orderFrontRegardless()
        installEventMonitors()
    }

    func close() {
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        removeEventMonitors()
        if wasVisible { closeHandler?() }
    }

    private func buildPanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        rootView.material = .hudWindow
        rootView.blendingMode = .behindWindow
        rootView.appearance = NSAppearance(named: .vibrantDark)
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 20
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 1
        rootView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        rootView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = rootView

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .gravityAreas
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            contentStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -12)
        ])

        rebuildContent()
    }

    private func rebuildContent() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        modeButtons.removeAll()

        contentStack.addArrangedSubview(headerView())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(sectionTitle("Mode"))
        contentStack.addArrangedSubview(modeRow(mode: .systemAuto, title: "System Auto", subtitle: "Use macOS native fan control", symbol: "checkmark.circle"))
        contentStack.addArrangedSubview(modeRow(mode: .preset(.silent), title: "Silent", subtitle: "Low noise", symbol: "speaker.wave.1"))
        contentStack.addArrangedSubview(modeRow(mode: .preset(.balanced), title: "Balanced", subtitle: "Everyday cooling", symbol: "fan"))
        contentStack.addArrangedSubview(modeRow(mode: .preset(.cool), title: "Cool", subtitle: "More airflow", symbol: "snowflake"))
        contentStack.addArrangedSubview(modeRow(mode: .preset(.max), title: "Max", subtitle: "Maximum fan speed", symbol: "wind"))
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(manualRow())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(launchRow())
        contentStack.addArrangedSubview(separator())
        contentStack.addArrangedSubview(quitRow())
        refreshControls()
    }

    private func headerView() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = text("MacFan", size: 17, weight: .semibold)
        stack.addArrangedSubview(title)

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 18
        grid.translatesAutoresizingMaskIntoConstraints = false

        temperatureValueLabel = valueText("--°")
        rpmValueLabel = valueText("—")
        fanStateLabel = valueText("Unavailable")

        grid.addRow(with: [mutedText("CPU / SoC"), temperatureValueLabel!])
        grid.addRow(with: [mutedText("Fan"), fanStateLabel!])
        grid.addRow(with: [mutedText("RPM"), rpmValueLabel!])
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .trailing
        stack.addArrangedSubview(grid)

        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: panelSize.width - 36),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return padded(stack, top: 6, bottom: 16)
    }

    private func modeRow(mode: FanMode, title: String, subtitle: String, symbol: String) -> NSView {
        let button = RowButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = #selector(modePressed(_:))
        button.identifier = NSUserInterfaceItemIdentifier(mode.identifier)
        button.translatesAutoresizingMaskIntoConstraints = false
        modeButtons[mode.identifier] = button

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let check = NSImageView()
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        check.contentTintColor = .controlAccentColor
        check.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        check.identifier = NSUserInterfaceItemIdentifier("check")
        check.translatesAutoresizingMaskIntoConstraints = false
        check.widthAnchor.constraint(equalToConstant: 18).isActive = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.symbolConfiguration = .init(pointSize: 20, weight: .regular)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.addArrangedSubview(text(title, size: 15, weight: .medium))
        labels.addArrangedSubview(mutedText(subtitle, size: 12))

        row.addArrangedSubview(check)
        row.addArrangedSubview(icon)
        row.addArrangedSubview(labels)
        button.addSubview(row)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: panelSize.width - 36),
            button.heightAnchor.constraint(equalToConstant: 50),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 0),
            row.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }

    private func manualRow() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 12
        top.translatesAutoresizingMaskIntoConstraints = false
        top.addArrangedSubview(labelPair(title: "Manual Linear Control", subtitle: "Set an exact fan speed"))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(spacer)

        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(manualSwitchChanged(_:))
        manualSwitch = toggle
        top.addArrangedSubview(toggle)
        container.addArrangedSubview(top)

        let sliderRow = NSStackView()
        sliderRow.orientation = .vertical
        sliderRow.alignment = .leading
        sliderRow.spacing = 4
        sliderRow.identifier = NSUserInterfaceItemIdentifier("manualSliderRow")
        sliderRow.translatesAutoresizingMaskIntoConstraints = false

        let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(manualSliderChanged(_:)))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        manualSlider = slider

        manualValueLabel = mutedText("—", size: 12)
        sliderRow.addArrangedSubview(slider)
        sliderRow.addArrangedSubview(manualValueLabel!)
        container.addArrangedSubview(sliderRow)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: panelSize.width - 36),
            top.widthAnchor.constraint(equalTo: container.widthAnchor),
            slider.widthAnchor.constraint(equalTo: container.widthAnchor)
        ])
        return padded(container, top: 12, bottom: 12)
    }

    private func launchRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(labelPair(title: "Launch at Login", subtitle: "Show temperature automatically"))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(launchSwitchChanged(_:))
        launchSwitch = toggle
        row.addArrangedSubview(toggle)

        NSLayoutConstraint.activate([row.widthAnchor.constraint(equalToConstant: panelSize.width - 36)])
        return padded(row, top: 12, bottom: 12)
    }

    private func quitRow() -> NSView {
        let button = RowButton()
        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = #selector(quitPressed)
        button.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(systemSymbolName: "power", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemRed
        icon.symbolConfiguration = .init(pointSize: 16, weight: .medium)
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        row.addArrangedSubview(icon)
        row.addArrangedSubview(text("Quit MacFan", size: 15, weight: .medium))

        button.addSubview(row)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: panelSize.width - 36),
            button.heightAnchor.constraint(equalToConstant: 42),
            row.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            row.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        return button
    }

    private func sectionTitle(_ title: String) -> NSView {
        padded(mutedText(title, size: 13, weight: .semibold), top: 16, bottom: 6)
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        box.widthAnchor.constraint(equalToConstant: panelSize.width - 54).isActive = true
        return padded(box, top: 0, bottom: 0, left: 18, right: 0)
    }

    private func labelPair(title: String, subtitle: String) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.addArrangedSubview(text(title, size: 15, weight: .medium))
        stack.addArrangedSubview(mutedText(subtitle, size: 12))
        return stack
    }

    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func mutedText(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = text(value, size: size, weight: weight)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func valueText(_ value: String) -> NSTextField {
        let label = text(value, size: 14, weight: .medium)
        label.alignment = .right
        label.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        return label
    }

    private func padded(_ view: NSView, top: CGFloat, bottom: CGFloat, left: CGFloat = 0, right: CGFloat = 0) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: left),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -right),
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: top),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bottom)
        ])
        return container
    }

    private func refreshControls() {
        temperatureValueLabel?.stringValue = store.snapshot.temperatureCelsius.map { "\($0)°" } ?? "--°"
        rpmValueLabel?.stringValue = store.snapshot.currentRPM.map { "\($0) RPM" } ?? "—"
        fanStateLabel?.stringValue = store.snapshot.isControlAvailable ? store.mode.displayName : "Unavailable"
        manualSwitch?.state = manualEnabled ? .on : .off
        launchSwitch?.state = loginItemManager.isLaunchAtLoginEnabled ? .on : .off

        for (identifier, button) in modeButtons {
            guard let mode = FanMode(identifier: identifier) else { continue }
            let selected = mode == store.mode
            button.alphaValue = store.snapshot.isControlAvailable || mode == .systemAuto ? 1.0 : 0.45
            button.isEnabled = store.snapshot.isControlAvailable || mode == .systemAuto
            button.subviews
                .compactMap { $0 as? NSStackView }
                .flatMap { $0.arrangedSubviews }
                .filter { $0.identifier?.rawValue == "check" }
                .forEach { $0.isHidden = !selected }
        }

        if let range = store.snapshot.range {
            manualSlider?.minValue = Double(range.minRPM)
            manualSlider?.maxValue = Double(range.maxRPM)
            if manualSlider?.doubleValue == 0 {
                manualSlider?.doubleValue = Double(max(store.snapshot.currentRPM ?? range.minRPM, range.minRPM))
            }
        }
        manualSlider?.isEnabled = manualEnabled && store.snapshot.isControlAvailable
        manualSlider?.superview?.isHidden = !manualEnabled
        manualValueLabel?.stringValue = "\(Int(manualSlider?.doubleValue.rounded() ?? 0)) RPM"
        manualSwitch?.isEnabled = store.snapshot.isControlAvailable
    }

    @objc private func modePressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let mode = FanMode(identifier: raw) else { return }
        manualEnabled = false
        Task {
            switch mode {
            case .systemAuto:
                try? await store.returnToSystemAuto()
            case .preset(let preset):
                try? await store.selectPreset(preset)
            case .manualLinear:
                break
            }
            await store.refreshSnapshot()
            refreshControls()
        }
    }

    @objc private func manualSwitchChanged(_ sender: NSSwitch) {
        manualEnabled = sender.state == .on
        if manualEnabled { seedManualSlider() }
        Task {
            if manualEnabled {
                try? await store.setManualRPM(Int(manualSlider?.doubleValue.rounded() ?? 0))
            } else {
                try? await store.returnToSystemAuto()
            }
            await store.refreshSnapshot()
            refreshControls()
        }
        refreshControls()
    }

    @objc private func manualSliderChanged(_ sender: NSSlider) {
        manualValueLabel?.stringValue = "\(Int(sender.doubleValue.rounded())) RPM"
        Task {
            try? await store.setManualRPM(Int(sender.doubleValue.rounded()))
            await store.refreshSnapshot()
            refreshControls()
        }
    }

    @objc private func launchSwitchChanged(_ sender: NSSwitch) {
        loginItemManager.setLaunchAtLogin(sender.state == .on)
        refreshControls()
    }

    @objc private func quitPressed() {
        close()
        onQuit()
    }

    private func seedManualSlider() {
        if let current = store.snapshot.currentRPM, current > 0 {
            manualSlider?.doubleValue = Double(current)
        } else if let minRPM = store.snapshot.range?.minRPM {
            manualSlider?.doubleValue = Double(minRPM)
        }
    }

    private func panelFrame(anchoredTo button: NSStatusBarButton) -> NSRect {
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = button.window?.convertToScreen(buttonFrame) ?? .zero
        let screen = button.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let x = min(max(screenFrame.midX - panelSize.width / 2, visible.minX + 8), visible.maxX - panelSize.width - 8)
        let y = screenFrame.minY - panelSize.height - 6
        return NSRect(x: x, y: max(y, visible.minY + 8), width: panelSize.width, height: panelSize.height)
    }

    private func installEventMonitors() {
        removeEventMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }
            if let window = event.window, window == self.panel { return event }
            self.close()
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeEventMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }
}

private final class NativeMenuPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RoundedVisualEffectView: NSVisualEffectView {}

private final class RowButton: NSButton {
    override func updateLayer() {
        super.updateLayer()
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
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
        } else if identifier.hasPrefix("preset."), let raw = identifier.split(separator: ".").last, let preset = FanPreset(rawValue: String(raw)) {
            self = .preset(preset)
        } else {
            return nil
        }
    }
}
