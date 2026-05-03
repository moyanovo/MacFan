import Testing
@testable import MacFanCore

actor RecordingFanClient: FanControlClient {
    var snapshotValue = FanSnapshot(temperatureCelsius: 52, currentRPM: 1800, range: FanRange(minRPM: 1200, maxRPM: 7200), isControlAvailable: true)
    private(set) var restoredSystemAutoCount = 0
    private(set) var targetRPMs: [Int] = []

    func snapshot() async -> FanSnapshot { snapshotValue }

    func restoreSystemAuto() async throws {
        restoredSystemAutoCount += 1
    }

    func setTargetRPM(_ rpm: Int) async throws {
        targetRPMs.append(rpm)
    }
}

@MainActor
@Suite
struct FanStateStoreTests {
    @Test func startsInSystemAutoAndRefreshesSnapshot() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        await store.refreshSnapshot()

        #expect(store.mode == .systemAuto)
        #expect(store.snapshot.temperatureCelsius == 52)
    }

    @Test func selectingPresetWritesCalculatedRPM() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.selectPreset(.balanced)

        let writes = await client.targetRPMs
        #expect(store.mode == .preset(.balanced))
        #expect(writes == [3300])
    }

    @Test func returningToSystemAutoRestoresAuto() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.returnToSystemAuto()

        let restores = await client.restoredSystemAutoCount
        #expect(store.mode == .systemAuto)
        #expect(restores == 1)
    }

    @Test func manualWriteUsesRangeAndThrottle() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client, manualWritePolicy: ManualWritePolicy(minimumInterval: 0.35, minimumDeltaRPM: 100))

        try await store.setManualRPM(2100, now: 0.0)
        try await store.setManualRPM(2150, now: 0.40)
        try await store.setManualRPM(2250, now: 0.40)

        let writes = await client.targetRPMs
        #expect(store.mode == .manualLinear)
        #expect(writes == [2100, 2250])
    }

    @Test func quitRestoresSystemAuto() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        await store.prepareForQuit()

        let restores = await client.restoredSystemAutoCount
        #expect(restores == 1)
    }
}
