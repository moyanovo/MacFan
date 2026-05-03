# MacFan

MacFan is a lightweight native macOS menu bar fan controller prototype optimized for:

- MacBook Pro, 13-inch, M1, 2020
- 8 GB memory
- macOS 26.5 Beta build 25F5058e

## Current implementation

Implemented now:

- Native Swift/AppKit menu bar app with no Dock icon.
- Menu bar title shows CPU / SoC temperature when the helper can read it, otherwise `--°`.
- Native SwiftUI popover with macOS material styling.
- Default `System Auto` mode.
- Manual presets: `Silent`, `Balanced`, `Cool`, `Max`.
- Manual linear RPM slider with throttled writes.
- First-launch `Launch MacFan at login?` prompt plus popover toggle.
- Bottom `Quit MacFan` button that asks the helper to restore System Auto before quitting.
- Best-effort AppleSMC helper boundary with safe fallback.

## Important beta-system note

On the current macOS 26.5 beta machine, the helper can open the AppleSMC service but direct SMC key reads currently return unavailable. The app therefore safely displays `--°` and disables fan controls instead of crashing or retrying aggressively.

That fallback is intentional: this project prioritizes low overhead and safe System Auto behavior over forcing private beta-system interfaces.

## Build and verify

The installed Command Line Tools expose Swift Testing from a nonstandard framework location, so use these commands in this environment:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --enable-swift-testing

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift build --product MacFanApp

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift build --product MacFanHelper
```

Smoke-test the helper:

```bash
./.build/debug/MacFanHelper snapshot
```

Expected safe fallback on the current beta system:

```text
temperature=nil currentRPM=nil minRPM=nil maxRPM=nil control=false source=AppleSMC reason=smc_keys_unreadable
```

## Run locally

Build both products first, then run the app with the helper path:

```bash
swift build --product MacFanHelper
swift build --product MacFanApp
MACFAN_HELPER_PATH=$PWD/.build/debug/MacFanHelper ./.build/debug/MacFanApp
```

## Design docs

- `docs/superpowers/specs/2026-05-02-macfan-design.md`
- `docs/superpowers/plans/2026-05-02-macfan-implementation.md`
