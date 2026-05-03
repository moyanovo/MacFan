import AppKit
import MacFanCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: FanStateStore
    @ObservedObject var loginItemManager: LoginItemManager
    let onQuit: () -> Void

    @State private var manualLinearEnabled = false
    @State private var manualRPM: Double = 0
    @State private var hoveredMode: FanMode?

    private var temperatureText: String {
        store.snapshot.temperatureCelsius.map { "\($0)°" } ?? "--°"
    }

    private var currentRPMText: String {
        store.snapshot.currentRPM.map { "\($0) RPM" } ?? "—"
    }

    private var fanText: String {
        if !store.snapshot.isControlAvailable { return "Unavailable" }
        return store.mode.displayName
    }

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                headerCard
                modesCard
                manualCard
                settingsCard
                quitCard
            }
            .padding(10)
        }
        .frame(width: 324)
        .fixedSize(horizontal: false, vertical: true)
        .task { await refreshInitialState() }
    }

    private var headerCard: some View {
        nativeCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.blue.gradient)
                        .frame(width: 42, height: 42)
                    Image(systemName: "fan.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacFan")
                        .font(.headline)
                    Text(fanText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(temperatureText)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(currentRPMText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var modesCard: some View {
        nativeCard(spacing: 0) {
            sectionLabel("Mode")
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            modeRow(.systemAuto, title: "System Auto", subtitle: "Use macOS native fan control", symbol: "checkmark.circle") {
                manualLinearEnabled = false
                Task { try? await store.returnToSystemAuto() }
            }

            nativeDivider

            ForEach(FanPreset.allCases) { preset in
                modeRow(.preset(preset), title: preset.displayName, subtitle: subtitle(for: preset), symbol: symbol(for: preset)) {
                    manualLinearEnabled = false
                    Task { try? await store.selectPreset(preset) }
                }
                .disabled(!store.snapshot.isControlAvailable)

                if preset != FanPreset.allCases.last {
                    nativeDivider
                }
            }

            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    private var manualCard: some View {
        nativeCard(spacing: 10) {
            Toggle(isOn: Binding(
                get: { manualLinearEnabled },
                set: { newValue in
                    manualLinearEnabled = newValue
                    if newValue {
                        seedManualRPM()
                        Task { try? await store.setManualRPM(Int(manualRPM.rounded())) }
                    } else {
                        Task { try? await store.returnToSystemAuto() }
                    }
                }
            )) {
                rowTitle("Manual Linear Control", subtitle: "Set an exact fan speed")
            }
            .toggleStyle(.switch)
            .controlSize(.regular)
            .disabled(!store.snapshot.isControlAvailable)

            if manualLinearEnabled, let range = store.snapshot.range {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { manualRPM },
                            set: { newValue in
                                manualRPM = newValue
                                Task { try? await store.setManualRPM(Int(newValue.rounded())) }
                            }
                        ),
                        in: Double(range.minRPM)...Double(range.maxRPM)
                    )
                    .controlSize(.small)

                    HStack {
                        Text("\(range.minRPM)")
                        Spacer()
                        Text("\(Int(manualRPM.rounded())) RPM")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(range.maxRPM)")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
    }

    private var settingsCard: some View {
        nativeCard(spacing: 10) {
            Toggle(isOn: Binding(
                get: { loginItemManager.isLaunchAtLoginEnabled },
                set: { loginItemManager.setLaunchAtLogin($0) }
            )) {
                rowTitle("Launch at Login", subtitle: "Show temperature automatically")
            }
            .toggleStyle(.switch)
            .controlSize(.regular)

            if !loginItemManager.hasAskedLaunchAtLogin {
                HStack(spacing: 8) {
                    Button("Not Now") { loginItemManager.markAsked() }
                    Button("Enable") { loginItemManager.setLaunchAtLogin(true) }
                        .keyboardShortcut(.defaultAction)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var quitCard: some View {
        nativeCard(spacing: 0) {
            Button(action: onQuit) {
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .foregroundStyle(.red)
                    Text("Quit MacFan")
                    Spacer()
                }
                .font(.body)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func nativeCard<Content: View>(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            content()
        }
        .padding(spacing == 0 ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func modeRow(_ mode: FanMode, title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(store.mode == mode ? .blue : .secondary)
                    .frame(width: 22)

                rowTitle(title, subtitle: subtitle)

                Spacer(minLength: 8)

                if store.mode == mode {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .contentShape(Rectangle())
            .background(rowBackground(for: mode))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredMode = hovering ? mode : nil }
    }

    @ViewBuilder
    private func rowBackground(for mode: FanMode) -> some View {
        if hoveredMode == mode {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.primary.opacity(0.06))
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
        }
    }

    private func rowTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var nativeDivider: some View {
        Divider().padding(.leading, 44)
    }

    private func subtitle(for preset: FanPreset) -> String {
        switch preset {
        case .silent: "Low noise"
        case .balanced: "Everyday cooling"
        case .cool: "More airflow"
        case .max: "Maximum fan speed"
        }
    }

    private func symbol(for preset: FanPreset) -> String {
        switch preset {
        case .silent: "speaker.wave.1"
        case .balanced: "fan"
        case .cool: "snowflake"
        case .max: "wind"
        }
    }

    private func refreshInitialState() async {
        await store.refreshSnapshot()
        seedManualRPM()
    }

    private func seedManualRPM() {
        if let current = store.snapshot.currentRPM, current > 0 {
            manualRPM = Double(current)
        } else if let minRPM = store.snapshot.range?.minRPM {
            manualRPM = Double(minRPM)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
