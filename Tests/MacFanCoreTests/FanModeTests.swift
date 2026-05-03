import Testing
@testable import MacFanCore

@Suite
struct FanModeTests {
    @Test func presetTargetsAreComputedFromFanRange() {
        let range = FanRange(minRPM: 1200, maxRPM: 7200)

        #expect(FanPreset.silent.targetRPM(in: range) == 2100)
        #expect(FanPreset.balanced.targetRPM(in: range) == 3300)
        #expect(FanPreset.cool.targetRPM(in: range) == 5100)
        #expect(FanPreset.max.targetRPM(in: range) == 7200)
    }

    @Test func presetTargetsClampToRange() {
        let collapsed = FanRange(minRPM: 2000, maxRPM: 2000)

        #expect(FanPreset.silent.targetRPM(in: collapsed) == 2000)
        #expect(FanPreset.max.targetRPM(in: collapsed) == 2000)
    }

    @Test func modeDisplayNamesMatchRequestedUI() {
        #expect(FanMode.systemAuto.displayName == "System Auto")
        #expect(FanMode.preset(.silent).displayName == "Silent")
        #expect(FanMode.preset(.balanced).displayName == "Balanced")
        #expect(FanMode.preset(.cool).displayName == "Cool")
        #expect(FanMode.preset(.max).displayName == "Max")
        #expect(FanMode.manualLinear.displayName == "Manual")
    }
}
