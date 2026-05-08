import Testing
@testable import MacFanCore

@Suite
struct PerformancePolicyTests {
    @Test func closedMenuPollingIsLowFrequency() {
        #expect(PerformancePolicy.closedMenuTemperatureInterval == 10.0)
    }

    @Test func openMenuPollingIsStillModerate() {
        #expect(PerformancePolicy.openMenuRefreshInterval == 1.0)
    }

    @Test func manualRPMWritesAreThrottledByTimeAndDelta() {
        let policy = ManualWritePolicy(minimumInterval: 0.35, minimumDeltaRPM: 100)

        #expect(policy.shouldWrite(lastWriteTime: nil, lastRPM: nil, newTime: 0.0, newRPM: 2100))
        #expect(!policy.shouldWrite(lastWriteTime: 0.0, lastRPM: 2100, newTime: 0.10, newRPM: 2400))
        #expect(!policy.shouldWrite(lastWriteTime: 0.0, lastRPM: 2100, newTime: 0.40, newRPM: 2150))
        #expect(policy.shouldWrite(lastWriteTime: 0.0, lastRPM: 2100, newTime: 0.40, newRPM: 2250))
    }
}
