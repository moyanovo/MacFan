# MacFan Initial MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight native Swift menu bar MVP that defaults to macOS System Auto, shows CPU / SoC temperature in the menu bar, exposes the requested manual controls in a native popover, and degrades safely when low-level fan control is unavailable.

**Architecture:** Use a Swift Package with a small testable `MacFanCore` library, a native AppKit/SwiftUI `MacFanApp` executable, and a minimal `MacFanHelper` executable containing the low-level SMC adapter boundary. Keep fan-policy logic in the core library, UI in the app target, and direct SMC calls behind `FanControlClient` so unsupported beta-system behavior becomes a disabled-control state instead of a crash.

**Tech Stack:** Swift 6.3, Swift Package Manager, XCTest, AppKit `NSStatusItem`, SwiftUI, `NSVisualEffectView` / materials, ServiceManagement `SMAppService`, IOKit for best-effort SMC access.

---

## File Map

- Create `/Users/huangmoyan/Desktop/MacFan/Package.swift` for the Swift package, macOS platform, app executable, helper executable, core library, and test target.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanMode.swift` for fan mode enums and preset RPM calculation.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanControlTypes.swift` for snapshots, fan ranges, availability, and client protocol.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/PerformancePolicy.swift` for poll intervals and slider write throttling.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanStateStore.swift` for state transitions and command dispatch.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/MacFanApp.swift` for `NSApplication` bootstrap with no Dock icon.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/MenuBarController.swift` for the status item, temperature title, timer, and popover.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/PopoverView.swift` for the macOS-style material UI and requested controls.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/FanControlClient.swift` for the app-side fallback client used by the MVP.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/LoginItemManager.swift` for first-launch prompting and launch-at-login toggling.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanHelper/main.swift` for a tiny command interface useful during development.
- Create `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanHelper/SMCClient.swift` for a best-effort AppleSMC/IOKit boundary.
- Create `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/FanModeTests.swift` for preset math tests.
- Create `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/PerformancePolicyTests.swift` for polling and throttling tests.
- Create `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/FanStateStoreTests.swift` for System Auto, preset, manual, and quit safety behavior.

---

## Task 1: Swift Package Baseline

**Files:**
- Create: `/Users/huangmoyan/Desktop/MacFan/Package.swift`
- Modify: `/Users/huangmoyan/Desktop/MacFan/.gitignore`

- [ ] **Step 1: Update `.gitignore` for local artifacts and worktrees**

Write:

```gitignore
.DS_Store
.build/
.swiftpm/
.worktrees/
```

- [ ] **Step 2: Create package manifest**

Write `/Users/huangmoyan/Desktop/MacFan/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacFanCore", targets: ["MacFanCore"]),
        .executable(name: "MacFanApp", targets: ["MacFanApp"]),
        .executable(name: "MacFanHelper", targets: ["MacFanHelper"])
    ],
    targets: [
        .target(name: "MacFanCore"),
        .executableTarget(
            name: "MacFanApp",
            dependencies: ["MacFanCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "MacFanHelper",
            dependencies: ["MacFanCore"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(name: "MacFanCoreTests", dependencies: ["MacFanCore"])
    ]
)
```

- [ ] **Step 3: Run baseline package resolution**

Run:

```bash
swift package describe
```

Expected: package graph prints with `MacFanCore`, `MacFanApp`, `MacFanHelper`, and `MacFanCoreTests`.

- [ ] **Step 4: Commit**

Run:

```bash
git add .gitignore Package.swift
git commit -m "build: add Swift package baseline"
```

---

## Task 2: Core Fan Modes and Preset RPM Math

**Files:**
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanMode.swift`
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanControlTypes.swift`
- Test: `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/FanModeTests.swift`

- [ ] **Step 1: Write failing tests for preset math**

Write `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/FanModeTests.swift`:

```swift
import XCTest
@testable import MacFanCore

final class FanModeTests: XCTestCase {
    func testPresetTargetsAreComputedFromFanRange() {
        let range = FanRange(minRPM: 1200, maxRPM: 7200)

        XCTAssertEqual(FanPreset.silent.targetRPM(in: range), 2100)
        XCTAssertEqual(FanPreset.balanced.targetRPM(in: range), 3300)
        XCTAssertEqual(FanPreset.cool.targetRPM(in: range), 5100)
        XCTAssertEqual(FanPreset.max.targetRPM(in: range), 7200)
    }

    func testPresetTargetsClampToRange() {
        let collapsed = FanRange(minRPM: 2000, maxRPM: 2000)

        XCTAssertEqual(FanPreset.silent.targetRPM(in: collapsed), 2000)
        XCTAssertEqual(FanPreset.max.targetRPM(in: collapsed), 2000)
    }

    func testModeDisplayNamesMatchRequestedUI() {
        XCTAssertEqual(FanMode.systemAuto.displayName, "System Auto")
        XCTAssertEqual(FanMode.preset(.silent).displayName, "Silent")
        XCTAssertEqual(FanMode.preset(.balanced).displayName, "Balanced")
        XCTAssertEqual(FanMode.preset(.cool).displayName, "Cool")
        XCTAssertEqual(FanMode.preset(.max).displayName, "Max")
        XCTAssertEqual(FanMode.manualLinear.displayName, "Manual")
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter FanModeTests
```

Expected: FAIL because `MacFanCore` types do not exist yet.

- [ ] **Step 3: Implement minimal core types**

Write `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanControlTypes.swift`:

```swift
import Foundation

public struct FanRange: Equatable, Sendable {
    public let minRPM: Int
    public let maxRPM: Int

    public init(minRPM: Int, maxRPM: Int) {
        self.minRPM = min(minRPM, maxRPM)
        self.maxRPM = max(minRPM, maxRPM)
    }

    public func clamped(_ rpm: Int) -> Int {
        min(max(rpm, minRPM), maxRPM)
    }
}

public struct FanSnapshot: Equatable, Sendable {
    public let temperatureCelsius: Int?
    public let currentRPM: Int?
    public let range: FanRange?
    public let isControlAvailable: Bool

    public init(temperatureCelsius: Int?, currentRPM: Int?, range: FanRange?, isControlAvailable: Bool) {
        self.temperatureCelsius = temperatureCelsius
        self.currentRPM = currentRPM
        self.range = range
        self.isControlAvailable = isControlAvailable
    }

    public static let unavailable = FanSnapshot(
        temperatureCelsius: nil,
        currentRPM: nil,
        range: nil,
        isControlAvailable: false
    )
}

public protocol FanControlClient: Sendable {
    func snapshot() async -> FanSnapshot
    func restoreSystemAuto() async throws
    func setTargetRPM(_ rpm: Int) async throws
}
```

Write `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanMode.swift`:

```swift
import Foundation

public enum FanPreset: String, CaseIterable, Equatable, Sendable, Identifiable {
    case silent
    case balanced
    case cool
    case max

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .silent: "Silent"
        case .balanced: "Balanced"
        case .cool: "Cool"
        case .max: "Max"
        }
    }

    private var fraction: Double {
        switch self {
        case .silent: 0.15
        case .balanced: 0.35
        case .cool: 0.65
        case .max: 1.0
        }
    }

    public func targetRPM(in range: FanRange) -> Int {
        guard range.maxRPM > range.minRPM else { return range.minRPM }
        let span = Double(range.maxRPM - range.minRPM)
        let raw = Double(range.minRPM) + span * fraction
        return range.clamped(Int(raw.rounded()))
    }
}

public enum FanMode: Equatable, Sendable {
    case systemAuto
    case preset(FanPreset)
    case manualLinear

    public var displayName: String {
        switch self {
        case .systemAuto: "System Auto"
        case .preset(let preset): preset.displayName
        case .manualLinear: "Manual"
        }
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
swift test --filter FanModeTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/MacFanCore Tests/MacFanCoreTests/FanModeTests.swift
git commit -m "feat: add fan mode model"
```

---

## Task 3: Performance Policy

**Files:**
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/PerformancePolicy.swift`
- Test: `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/PerformancePolicyTests.swift`

- [ ] **Step 1: Write failing tests for low-overhead policy**

Write `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/PerformancePolicyTests.swift`:

```swift
import XCTest
@testable import MacFanCore

final class PerformancePolicyTests: XCTestCase {
    func testClosedPopoverPollingIsLowFrequency() {
        XCTAssertEqual(PerformancePolicy.closedPopoverTemperatureInterval, 5.0)
    }

    func testOpenPopoverPollingIsStillModerate() {
        XCTAssertEqual(PerformancePolicy.openPopoverRefreshInterval, 1.0)
    }

    func testManualRPMWritesAreThrottledByTimeAndDelta() {
        let policy = ManualWritePolicy(minimumInterval: 0.35, minimumDeltaRPM: 100)

        XCTAssertTrue(policy.shouldWrite(lastWriteTime: nil, lastRPM: nil, newTime: 0.0, newRPM: 2100))
        XCTAssertFalse(policy.shouldWrite(lastWriteTime: 0.0, lastRPM: 2100, newTime: 0.10, newRPM: 2400))
        XCTAssertFalse(policy.shouldWrite(lastWriteTime: 0.0, lastRPM: 2100, newTime: 0.40, newRPM: 2150))
        XCTAssertTrue(policy.shouldWrite(lastWriteTime: 0.0, lastRPM: 2100, newTime: 0.40, newRPM: 2250))
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter PerformancePolicyTests
```

Expected: FAIL because `PerformancePolicy` and `ManualWritePolicy` do not exist.

- [ ] **Step 3: Implement policy**

Write `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/PerformancePolicy.swift`:

```swift
import Foundation

public enum PerformancePolicy {
    public static let closedPopoverTemperatureInterval: TimeInterval = 5.0
    public static let openPopoverRefreshInterval: TimeInterval = 1.0
}

public struct ManualWritePolicy: Sendable {
    public let minimumInterval: TimeInterval
    public let minimumDeltaRPM: Int

    public init(minimumInterval: TimeInterval = 0.35, minimumDeltaRPM: Int = 100) {
        self.minimumInterval = minimumInterval
        self.minimumDeltaRPM = minimumDeltaRPM
    }

    public func shouldWrite(lastWriteTime: TimeInterval?, lastRPM: Int?, newTime: TimeInterval, newRPM: Int) -> Bool {
        guard let lastWriteTime, let lastRPM else { return true }
        guard newTime - lastWriteTime >= minimumInterval else { return false }
        return abs(newRPM - lastRPM) >= minimumDeltaRPM
    }
}
```

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
swift test --filter PerformancePolicyTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/MacFanCore/PerformancePolicy.swift Tests/MacFanCoreTests/PerformancePolicyTests.swift
git commit -m "feat: add performance policy"
```

---

## Task 4: Fan State Store and Safe Commands

**Files:**
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanStateStore.swift`
- Test: `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/FanStateStoreTests.swift`

- [ ] **Step 1: Write failing state-machine tests**

Write `/Users/huangmoyan/Desktop/MacFan/Tests/MacFanCoreTests/FanStateStoreTests.swift`:

```swift
import XCTest
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

final class FanStateStoreTests: XCTestCase {
    func testStartsInSystemAutoAndRefreshesSnapshot() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        await store.refreshSnapshot()

        XCTAssertEqual(store.mode, .systemAuto)
        XCTAssertEqual(store.snapshot.temperatureCelsius, 52)
    }

    func testSelectingPresetWritesCalculatedRPM() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.selectPreset(.balanced)

        let writes = await client.targetRPMs
        XCTAssertEqual(store.mode, .preset(.balanced))
        XCTAssertEqual(writes, [3300])
    }

    func testReturningToSystemAutoRestoresAuto() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        try await store.returnToSystemAuto()

        let restores = await client.restoredSystemAutoCount
        XCTAssertEqual(store.mode, .systemAuto)
        XCTAssertEqual(restores, 1)
    }

    func testManualWriteUsesRangeAndThrottle() async throws {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client, manualWritePolicy: ManualWritePolicy(minimumInterval: 0.35, minimumDeltaRPM: 100))

        try await store.setManualRPM(2100, now: 0.0)
        try await store.setManualRPM(2150, now: 0.40)
        try await store.setManualRPM(2250, now: 0.40)

        let writes = await client.targetRPMs
        XCTAssertEqual(store.mode, .manualLinear)
        XCTAssertEqual(writes, [2100, 2250])
    }

    func testQuitRestoresSystemAuto() async {
        let client = RecordingFanClient()
        let store = FanStateStore(client: client)

        await store.prepareForQuit()

        let restores = await client.restoredSystemAutoCount
        XCTAssertEqual(restores, 1)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter FanStateStoreTests
```

Expected: FAIL because `FanStateStore` does not exist.

- [ ] **Step 3: Implement state store**

Write `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanCore/FanStateStore.swift`:

```swift
import Foundation

@MainActor
public final class FanStateStore: ObservableObject {
    @Published public private(set) var mode: FanMode = .systemAuto
    @Published public private(set) var snapshot: FanSnapshot = .unavailable
    @Published public private(set) var lastErrorMessage: String?

    private let client: FanControlClient
    private let manualWritePolicy: ManualWritePolicy
    private var lastManualWriteTime: TimeInterval?
    private var lastManualRPM: Int?

    public init(client: FanControlClient, manualWritePolicy: ManualWritePolicy = ManualWritePolicy()) {
        self.client = client
        self.manualWritePolicy = manualWritePolicy
    }

    public func refreshSnapshot() async {
        snapshot = await client.snapshot()
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
```

- [ ] **Step 4: Run tests and verify GREEN**

Run:

```bash
swift test --filter FanStateStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/MacFanCore/FanStateStore.swift Tests/MacFanCoreTests/FanStateStoreTests.swift
git commit -m "feat: add fan state store"
```

---

## Task 5: App-Side Client, Login Manager, and Native UI

**Files:**
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/FanControlClient.swift`
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/LoginItemManager.swift`
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/PopoverView.swift`
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/MenuBarController.swift`
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanApp/MacFanApp.swift`

- [ ] **Step 1: Create app fallback fan client**

Write a client that compiles now and safely returns `.unavailable` until the helper IPC is wired:

```swift
import Foundation
import MacFanCore

struct AppFanControlClient: FanControlClient {
    func snapshot() async -> FanSnapshot {
        .unavailable
    }

    func restoreSystemAuto() async throws {}

    func setTargetRPM(_ rpm: Int) async throws {}
}
```

- [ ] **Step 2: Create login manager**

Write a small `@MainActor` manager using `UserDefaults` and `SMAppService.mainApp`:

```swift
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var hasAskedLaunchAtLogin: Bool
    @Published private(set) var isLaunchAtLoginEnabled: Bool

    private let defaults: UserDefaults
    private let askedKey = "hasAskedLaunchAtLogin"
    private let enabledKey = "isLaunchAtLoginEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasAskedLaunchAtLogin = defaults.bool(forKey: askedKey)
        isLaunchAtLoginEnabled = defaults.bool(forKey: enabledKey)
    }

    func markAsked() {
        hasAskedLaunchAtLogin = true
        defaults.set(true, forKey: askedKey)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isLaunchAtLoginEnabled = enabled
            defaults.set(enabled, forKey: enabledKey)
            markAsked()
        } catch {
            isLaunchAtLoginEnabled = false
            defaults.set(false, forKey: enabledKey)
            markAsked()
        }
    }
}
```

- [ ] **Step 3: Create popover view**

Build a SwiftUI view with native controls, no charts, and a visible bottom quit button. The view must bind to `FanStateStore`, disable controls when `snapshot.isControlAvailable == false`, and call `prepareForQuit()` before `NSApp.terminate(nil)`.

- [ ] **Step 4: Create menu bar controller**

Build an `NSStatusItem` controller that:

- Shows `NN°` when `snapshot.temperatureCelsius` exists.
- Shows `--°` when unavailable.
- Refreshes at `PerformancePolicy.closedPopoverTemperatureInterval` while closed.
- Uses `NSPopover` for the SwiftUI view.
- Uses no Dock icon.

- [ ] **Step 5: Create app entry point**

Create an `@main` type that starts `NSApplication`, sets `.accessory`, creates the store with `AppFanControlClient`, and installs `MenuBarController`.

- [ ] **Step 6: Build app target**

Run:

```bash
swift build --product MacFanApp
```

Expected: PASS.

- [ ] **Step 7: Commit**

Run:

```bash
git add Sources/MacFanApp
git commit -m "feat: add menu bar app UI"
```

---

## Task 6: Helper Boundary and Best-Effort SMC Adapter

**Files:**
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanHelper/main.swift`
- Create: `/Users/huangmoyan/Desktop/MacFan/Sources/MacFanHelper/SMCClient.swift`

- [ ] **Step 1: Create helper command interface**

Write a tiny command interface with `snapshot`, `auto`, and `rpm <value>` commands. It should print machine-readable one-line output and exit nonzero on invalid input.

- [ ] **Step 2: Create SMC adapter boundary**

Create `SMCClient` as the single location for AppleSMC / IOKit access. For version 1, expose methods matching the helper commands:

```swift
struct SMCClient {
    func snapshot() throws -> String
    func restoreSystemAuto() throws
    func setTargetRPM(_ rpm: Int) throws
}
```

If AppleSMC cannot be opened, `snapshot()` returns a string that represents unavailable state instead of crashing.

- [ ] **Step 3: Build helper target**

Run:

```bash
swift build --product MacFanHelper
```

Expected: PASS.

- [ ] **Step 4: Run helper snapshot smoke test**

Run:

```bash
swift run MacFanHelper snapshot
```

Expected: either a one-line available snapshot or a one-line unavailable snapshot; no crash.

- [ ] **Step 5: Commit**

Run:

```bash
git add Sources/MacFanHelper
git commit -m "feat: add helper SMC boundary"
```

---

## Task 7: Full Verification and Push

**Files:**
- Modify as needed only if verification exposes compile or test failures.

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Build both executable products**

Run:

```bash
swift build --product MacFanApp
swift build --product MacFanHelper
```

Expected: both builds pass.

- [ ] **Step 3: Inspect git status**

Run:

```bash
git status --short
```

Expected: clean except ignored macOS metadata files.

- [ ] **Step 4: Push branch**

Run:

```bash
git push -u origin feature/initial-mvp
```

Expected: branch pushed to GitHub.

---

## Self-Review Notes

- Spec coverage: this plan covers menu bar temperature display, native popover controls, System Auto default, four presets, manual slider, launch-at-login preference, quit safety, helper boundary, fallback behavior, and performance constraints.
- Scope control: this plan does not add charts, custom automatic curves, profiles, notifications, localization, or heavy runtimes.
- Known packaging boundary: this plan creates a SwiftPM runnable MVP and helper boundary. A notarized `.app` bundle and signed privileged helper installer should be a separate packaging plan after the MVP compiles and the UI/control state is validated.
