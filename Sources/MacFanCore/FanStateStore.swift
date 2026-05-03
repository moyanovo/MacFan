import Foundation

@MainActor
public final class FanStateStore {
    public private(set) var mode: FanMode = .systemAuto
    public private(set) var snapshot: FanSnapshot = .unavailable
    public private(set) var lastErrorMessage: String?

    private let client: any FanControlClient
    private let manualWritePolicy: ManualWritePolicy
    private var lastManualWriteTime: TimeInterval?
    private var lastManualRPM: Int?

    public init(client: any FanControlClient, manualWritePolicy: ManualWritePolicy = ManualWritePolicy()) {
        self.client = client
        self.manualWritePolicy = manualWritePolicy
    }

    public func refreshSnapshot() async {
        snapshot = await client.snapshot()
        if !snapshot.isControlAvailable {
            mode = .systemAuto
            lastManualWriteTime = nil
            lastManualRPM = nil
        }
    }

    public func returnToSystemAuto() async throws {
        try await client.restoreSystemAuto()
        mode = .systemAuto
        lastManualWriteTime = nil
        lastManualRPM = nil
        lastErrorMessage = nil
    }

    public func selectPreset(_ preset: FanPreset) async throws {
        let current = snapshot.range == nil ? await client.snapshot() : snapshot
        snapshot = current
        guard current.isControlAvailable, let range = current.range else {
            lastErrorMessage = "Fan control unavailable"
            return
        }
        let rpm = preset.targetRPM(in: range)
        try await client.setTargetRPM(rpm)
        mode = .preset(preset)
        lastManualWriteTime = nil
        lastManualRPM = rpm
        lastErrorMessage = nil
    }

    public func setManualRPM(_ rpm: Int, now: TimeInterval = Date().timeIntervalSince1970) async throws {
        let current = snapshot.range == nil ? await client.snapshot() : snapshot
        snapshot = current
        guard current.isControlAvailable, let range = current.range else {
            lastErrorMessage = "Fan control unavailable"
            return
        }
        let clamped = range.clamped(rpm)
        guard manualWritePolicy.shouldWrite(lastWriteTime: lastManualWriteTime, lastRPM: lastManualRPM, newTime: now, newRPM: clamped) else {
            return
        }
        try await client.setTargetRPM(clamped)
        mode = .manualLinear
        lastManualWriteTime = now
        lastManualRPM = clamped
        lastErrorMessage = nil
    }

    public func prepareForQuit() async {
        do {
            try await returnToSystemAuto()
        } catch {
            lastErrorMessage = "Could not restore System Auto"
        }
    }
}
