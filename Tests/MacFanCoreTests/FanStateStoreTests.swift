import Testing
@testable import MacFanCore

actor RecordingFanClient: FanControlClient {
    var snapshotValue = FanSnapshot(temperatureCelsius: 52, currentRPM: 1800, range: FanRange(minRPM: 1200, maxRPM: 7200), isControlAvailable: true)
    var temperatureValue: Int? = 52
    var shouldFailWrites = false
    private(set) var restoredSystemAutoCount = 0
    private(set) var temperatureReadCount = 0
    private(set) var snapshotReadCount = 0
    private(set) var targetRPMs: [Int] = []

    func temperatureCelsius() async -> Int? {
        temperatureReadCount += 1
        return temperatureValue
    }

    func snapshot() async -> FanSnapshot {
        snapshotReadCount += 1
        return snapshotValue
    }

    func setSnapshotValue(_ snapshot: FanSnapshot) {
        snapshotValue = snapshot
    }

    func setTemperatureValue(_ temperature: Int?) {
        temperatureValue = temperature
    }

    func setShouldFailWrites(_ shouldFail: Bool) {
        shouldFailWrites = shouldFail
    }

    func restoreSystemAuto() async throws {
        if shouldFailWrites { throw TestFanError.writeFailed }
        restoredSystemAutoCount += 1
    }

    func setTargetRPM(_ rpm: Int) async throws {
        if shouldFailWrites { throw TestFanError.writeFailed }
        targetRPMs.append(rpm)
    }
}

enum TestFanError: Error {
    case writeFailed
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

    @Test func refreshUnavailableFallsBackToSystemAuto() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.setManualRPM(2100, now: 0.0)
        await client.setSnapshotValue(.unavailable)
        await store.refreshSnapshot()

        #expect(store.mode == .systemAuto)
    }

    @Test func failedPresetWriteReportsErrorAndDoesNotChangeMode() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)
        await client.setShouldFailWrites(true)

        do {
            try await store.selectPreset(.balanced)
        } catch {}

        #expect(store.mode == .systemAuto)
        #expect(store.lastErrorMessage == "Could not set fan target")
    }

    @Test func failedManualWriteReportsErrorAndDoesNotChangeMode() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)
        await client.setShouldFailWrites(true)

        do {
            try await store.setManualRPM(2100, now: 0.0)
        } catch {}

        #expect(store.mode == .systemAuto)
        #expect(store.lastErrorMessage == "Could not set fan target")
    }

    @Test func failedSystemAutoRestoreReportsError() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)
        await client.setShouldFailWrites(true)

        do {
            try await store.returnToSystemAuto()
        } catch {}

        #expect(store.lastErrorMessage == "Could not restore System Auto")
    }

    @Test func temperatureOnlyRefreshDoesNotReadFanSnapshot() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        await store.refreshTemperatureOnly()

        let temperatureReads = await client.temperatureReadCount
        let snapshotReads = await client.snapshotReadCount
        #expect(store.snapshot.temperatureCelsius == 52)
        #expect(temperatureReads == 1)
        #expect(snapshotReads == 0)
    }

    @Test func manualTargetIsReassertedIfCurrentRPMDropsToZero() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.setManualRPM(2100, now: 0.0)
        await client.setSnapshotValue(FanSnapshot(temperatureCelsius: 52, currentRPM: 0, range: FanRange(minRPM: 1200, maxRPM: 7200), isControlAvailable: true))
        await store.refreshSnapshot(now: 6.0)

        let writes = await client.targetRPMs
        #expect(writes == [2100, 2100])
    }

    @Test func manualTargetIsNotReassertedBeforeInterval() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.setManualRPM(2100, now: 0.0)
        await client.setSnapshotValue(FanSnapshot(temperatureCelsius: 52, currentRPM: 0, range: FanRange(minRPM: 1200, maxRPM: 7200), isControlAvailable: true))
        await store.refreshSnapshot(now: 4.0)

        let writes = await client.targetRPMs
        #expect(writes == [2100])
    }
}
