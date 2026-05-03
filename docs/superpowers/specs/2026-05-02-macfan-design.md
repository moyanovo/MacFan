# MacFan Design Spec

## Goal

Build an extremely lightweight native macOS menu bar fan controller optimized for the user's machine:

- MacBook Pro, 13-inch, M1, 2020
- 8 GB memory
- macOS Version 26.5 Beta, build 25F5058e

MacFan should behave like a small system component: minimal idle CPU usage, minimal memory footprint, native macOS UI, and no unnecessary background work.

## Scope

Version 1 focuses on the required fan-control workflow only:

- Menu bar temperature display.
- Native popover control panel.
- Default macOS System Auto fan behavior.
- Four manual presets: Silent, Balanced, Cool, Max.
- Fully manual linear RPM control with a switch and slider.
- First-launch prompt for launch at login.
- Quit button at the bottom of the popover.
- Graceful fallback when helper or SMC access is unavailable.

Version 1 explicitly does not include:

- Custom automatic fan curves.
- Temperature history charts.
- Multi-sensor dashboards.
- Multiple profiles.
- Notification rules.
- iCloud sync.
- Localization.
- Menu bar icon themes.
- Electron, WebView, Node, or other heavy runtimes.

## Product Behavior

### Default Mode

MacFan starts in **System Auto** mode.

In System Auto mode:

- macOS keeps native control over fan behavior.
- MacFan does not write fan RPM values.
- The app only reads the CPU / SoC primary temperature for display.
- This is the default on every launch, even if the previous session used a manual mode.

Manual control is only active after the user explicitly selects a preset or enables manual linear control.

### Menu Bar Display

When the popover is closed, the menu bar item displays only the CPU / SoC primary temperature:

```text
52°
```

Rules:

- Display Celsius only in version 1.
- Do not show a fan icon, fan RPM, or extra status text in the menu bar.
- If temperature cannot be read, display:

```text
--°
```

- Keep sampling low-frequency while the popover is closed.
- Avoid rendering the full SwiftUI popover view while the popover is closed.

### Popover UI

Clicking the menu bar item opens a native macOS-style popover.

The popover should use system controls, system typography, system spacing, and a translucent material / vibrancy appearance consistent with macOS components.

Target layout:

```text
MacFan
CPU / SoC        52°
Fan              System Auto

Mode
● System Auto
○ Silent
○ Balanced
○ Cool
○ Max

Manual Linear Control
[ Off ]

Launch at Login
[ Ask / On / Off ]

────────────
Quit MacFan
```

When manual linear control is enabled:

```text
Manual Linear Control
[ On ]

RPM
[ slider ----------------- ]
2100 RPM
```

### Manual Presets

The four presets are calculated from the fan's reported minimum and maximum RPM instead of fixed absolute numbers.

Let:

- `minRPM` = helper-reported minimum fan speed.
- `maxRPM` = helper-reported maximum fan speed.
- `range = maxRPM - minRPM`.

Preset targets:

- Silent: `minRPM + 15% * range`
- Balanced: `minRPM + 35% * range`
- Cool: `minRPM + 65% * range`
- Max: `maxRPM`

The final RPM value is clamped to the reported `[minRPM, maxRPM]` range.

### Manual Linear Control

Manual linear control is separate from the preset list.

Rules:

- Turning it on shows a slider.
- Slider range is `[minRPM, maxRPM]`.
- Slider movement sets the target fan RPM.
- Writes are throttled to avoid excessive helper calls.
- RPM changes smaller than 100 RPM should not trigger writes.
- Turning manual linear control off immediately returns to System Auto.

Recommended write throttle for version 1: 300-500 ms.

### Quit Behavior

The bottom of the popover contains a visible `Quit MacFan` button.

When clicked:

1. Ask the helper to restore System Auto.
2. Stop app timers.
3. Quit the app.

If the helper call fails, the app may still quit, but it should make a best-effort attempt to release manual fan control first.

## Architecture

MacFan uses two small native components.

### MacFan.app

The app is a native Swift menu bar application.

Responsibilities:

- Own the `NSStatusItem` menu bar item.
- Display the CPU / SoC temperature in the menu bar.
- Show and hide the popover.
- Render the SwiftUI control UI.
- Store minimal user preferences.
- Register or unregister launch at login.
- Communicate with the helper through a narrow client API.
- Keep all UI and policy logic out of the helper.

The app has no Dock icon.

### MacFanHelper

The helper is a privileged helper responsible only for low-level fan and sensor operations.

Responsibilities:

- Read CPU / SoC primary temperature.
- Read fan minimum RPM.
- Read fan maximum RPM.
- Read fan current RPM.
- Restore System Auto fan mode.
- Set a target fan RPM.

The helper does not own UI, preferences, history, profiles, or custom automatic curves.

## Helper and SMC Strategy

MacFan should use a layered access strategy.

1. Prefer AppleSMC / IOKit access for real temperature and fan control.
2. If AppleSMC / IOKit access fails, the app remains usable but fan control is disabled.
3. If the helper is missing or broken, the popover shows a repair/install state instead of crashing.

Failure behavior:

- Menu bar temperature becomes `--°` when unavailable.
- Manual controls become disabled when fan control is unavailable.
- The app must not repeatedly retry in a tight loop.
- The app must not crash because a beta macOS build changes low-level behavior.

## Safety Rules

System Auto is the safety baseline.

Rules:

- App launch starts in System Auto.
- User must explicitly choose any manual override.
- Switching back to System Auto releases manual control immediately.
- Disabling manual linear control releases manual control immediately.
- Quitting attempts to restore System Auto first.
- Sleep/wake recovery should prefer System Auto unless the user manually chooses a mode again.
- Helper errors should fail closed toward System Auto or control-disabled behavior.

## Launch at Login

On first launch, MacFan asks once:

```text
Launch MacFan at login?
[Not Now] [Enable]
```

Rules:

- If the user selects Enable, register launch at login.
- If the user selects Not Now, do not enable it for that session.
- Do not repeatedly ask after the first decision.
- The popover includes a launch-at-login control for later changes.
- Use Apple's `SMAppService` APIs where possible.

## Configuration Persistence

Persist only minimal preferences:

- Whether the launch-at-login prompt has already been shown.
- Whether launch at login is enabled.

Do not persist:

- Previous manual mode.
- Previous manual RPM.
- Whether the manual slider was expanded.
- Any custom automatic curve.

This avoids accidental manual fan control after reboot or app restart.

## Performance Requirements

MacFan is designed around low idle cost.

Targets:

- Idle menu bar CPU usage should be near zero, with a target below 0.3%.
- Idle memory should stay small, with a target below 30-50 MB if practical for SwiftUI/AppKit.
- No high-frequency sensor polling while the popover is closed.
- No heavy runtime dependencies.
- No charts or continuous animation.
- No WebView or Electron.
- No duplicate UI/background processes unless required by macOS helper architecture.

Implementation rules:

- Keep the menu bar closed-state loop minimal.
- Refresh detailed fan information mainly when the popover is open.
- Throttle manual slider writes.
- Let the helper act on request instead of running an aggressive daemon loop.
- Prefer native Swift, SwiftUI, AppKit, IOKit, ServiceManagement, and XPC.

## Proposed File Structure

The project starts as a minimal native Swift project:

```text
/Users/huangmoyan/Desktop/MacFan
├── Package.swift
├── Sources/
│   ├── MacFanApp/
│   │   ├── MacFanApp.swift
│   │   ├── MenuBarController.swift
│   │   ├── PopoverView.swift
│   │   ├── FanMode.swift
│   │   ├── FanStateStore.swift
│   │   ├── FanControlClient.swift
│   │   ├── LoginItemManager.swift
│   │   └── PerformancePolicy.swift
│   └── MacFanHelper/
│       ├── main.swift
│       ├── SMCClient.swift
│       ├── FanController.swift
│       └── HelperProtocol.swift
├── Tests/
│   └── MacFanTests/
│       ├── FanModeTests.swift
│       ├── FanStateStoreTests.swift
│       └── PerformancePolicyTests.swift
└── docs/
    └── superpowers/
        └── specs/
```

## Testing and Verification

### Unit Tests

Version 1 should include tests for:

- Preset RPM calculation.
- RPM clamping.
- Manual slider write throttling.
- State transitions between System Auto, preset modes, and manual linear control.
- Helper-unavailable UI state.
- Launch-at-login preference state.

### Manual Verification

Manual verification on the user's Mac should confirm:

- First launch asks about launch at login.
- Menu bar shows CPU / SoC temperature as `NN°`.
- Temperature read failure displays `--°`.
- Popover visually matches native macOS components and uses material/vibrancy.
- Default mode is System Auto.
- System Auto does not write a fan RPM.
- Silent, Balanced, Cool, and Max set the expected target RPMs.
- Manual linear control shows a slider and writes throttled RPM values.
- Turning manual linear control off restores System Auto.
- Quit MacFan attempts to restore System Auto before exiting.
- Helper unavailable state disables fan controls without crashing.

## Success Criteria

The first completed version is successful when:

- It behaves as a lightweight menu bar utility rather than a full dashboard.
- The closed menu bar state only shows CPU / SoC temperature.
- The popover contains all requested controls.
- Default behavior remains macOS native System Auto.
- Manual control is explicit, reversible, and easy to exit.
- The app remains stable on macOS 26.5 Beta even if low-level SMC access fails.
- The implementation avoids speculative features and heavy dependencies.
