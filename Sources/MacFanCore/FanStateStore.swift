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
    private var targetRPM: Int?
    private var lastTargetWriteTime: TimeInterval?
    private let targetReassertInterval: TimeInterval = 5.0

    public init(client: any FanControlClient, manualWritePolicy: ManualWritePolicy = ManualWritePolicy()) {
        self.client = client
        self.manualWritePolicy = manualWritePolicy
    }

    public func refreshTemperatureOnly() async {
        let temperature = await client.temperatureCelsius()
        snapshot = FanSnapshot(
            temperatureCelsius: temperature,
            currentRPM: snapshot.currentRPM,
            range: snapshot.range,
            isControlAvailable: snapshot.isControlAvailable
        )
    }

    public func refreshSnapshot(now: TimeInterval = Date().timeIntervalSince1970) async {
        snapshot = await client.snapshot()
        if !snapshot.isControlAvailable {
            mode = .systemAuto
            lastManualWriteTime = nil
            lastManualRPM = nil
            targetRPM = nil
            lastTargetWriteTime = nil
            return
        }

        guard mode != .systemAuto,
              snapshot.currentRPM == 0,
              let rpm = targetRPM ?? lastManualRPM else {
            return
        }

        if let lastTargetWriteTime, now - lastTargetWriteTime < targetReassertInterval {
            return
        }

        do {
            try await client.setTargetRPM(rpm)
            lastTargetWriteTime = now
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Could not keep fan target"
        }
    }

    public func returnToSystemAuto() async throws {
        do {
            try await client.restoreSystemAuto()
        } catch {
            lastErrorMessage = "Could not restore System Auto"
            throw error
        }
        mode = .systemAuto
        lastManualWriteTime = nil
        lastManualRPM = nil
        targetRPM = nil
        lastTargetWriteTime = nil
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
        do {
            try await client.setTargetRPM(rpm)
        } catch {
            lastErrorMessage = "Could not set fan target"
            throw error
        }
        mode = .preset(preset)
        lastManualWriteTime = nil
        lastManualRPM = rpm
        targetRPM = rpm
        lastTargetWriteTime = Date().timeIntervalSince1970
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
        do {
            try await client.setTargetRPM(clamped)
        } catch {
            lastErrorMessage = "Could not set fan target"
            throw error
        }
        mode = .manualLinear
        lastManualWriteTime = now
        lastManualRPM = clamped
        targetRPM = clamped
        lastTargetWriteTime = now
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
