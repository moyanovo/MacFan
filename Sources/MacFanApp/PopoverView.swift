import AppKit
import MacFanCore
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: FanStateStore
    @ObservedObject var loginItemManager: LoginItemManager
    let onQuit: () -> Void

    @State private var manualLinearEnabled = false
    @State private var manualRPM: Double = 0

    private var temperatureText: String {
        store.snapshot.temperatureCelsius.map { "\($0)°" } ?? "--°"
    }

    private var fanText: String {
        if !store.snapshot.isControlAvailable { return "Unavailable" }
        return store.mode.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            modeSection
            manualSection
            launchSection
            Divider()
            quitButton
        }
        .padding(16)
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .task {
            await store.refreshSnapshot()
            if let current = store.snapshot.currentRPM {
                manualRPM = Double(current)
            } else if let minRPM = store.snapshot.range?.minRPM {
                manualRPM = Double(minRPM)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MacFan")
                .font(.headline)
            HStack {
                Text("CPU / SoC")
                Spacer()
                Text(temperatureText)
                    .monospacedDigit()
            }
            HStack {
                Text("Fan")
                Spacer()
                Text(fanText)
                    .foregroundStyle(store.snapshot.isControlAvailable ? .primary : .secondary)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode")
                .font(.subheadline.weight(.semibold))
            modeButton(.systemAuto, title: "System Auto") {
                manualLinearEnabled = false
                Task { try? await store.returnToSystemAuto() }
            }
            ForEach(FanPreset.allCases) { preset in
                modeButton(.preset(preset), title: preset.displayName) {
                    manualLinearEnabled = false
                    Task { try? await store.selectPreset(preset) }
                }
                .disabled(!store.snapshot.isControlAvailable)
            }
            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modeButton(_ mode: FanMode, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: store.mode == mode ? "largecircle.fill.circle" : "circle")
                    .imageScale(.small)
                Text(title)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Manual Linear Control", isOn: Binding(
                get: { manualLinearEnabled },
                set: { newValue in
                    manualLinearEnabled = newValue
                    if newValue {
                        if let current = store.snapshot.currentRPM {
                            manualRPM = Double(current)
                        } else if let minRPM = store.snapshot.range?.minRPM {
                            manualRPM = Double(minRPM)
                        }
                        Task { try? await store.setManualRPM(Int(manualRPM)) }
                    } else {
                        Task { try? await store.returnToSystemAuto() }
                    }
                }
            ))
            .disabled(!store.snapshot.isControlAvailable)

            if manualLinearEnabled, let range = store.snapshot.range {
                Text("RPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text("\(Int(manualRPM.rounded())) RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItemManager.isLaunchAtLoginEnabled },
                set: { loginItemManager.setLaunchAtLogin($0) }
            ))
            if !loginItemManager.hasAskedLaunchAtLogin {
                HStack {
                    Button("Not Now") { loginItemManager.markAsked() }
                    Spacer()
                    Button("Enable") { loginItemManager.setLaunchAtLogin(true) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var quitButton: some View {
        Button(role: .destructive, action: onQuit) {
            HStack {
                Spacer()
                Text("Quit MacFan")
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
