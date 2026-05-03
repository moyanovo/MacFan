# MacFan

MacFan is a lightweight native macOS menu bar fan controller prototype optimized for:

- MacBook Pro, 13-inch, M1, 2020
- 8 GB memory
- macOS 26.5 Beta build 25F5058e

## Current implementation

Implemented now:

- Native Swift/AppKit menu bar app with no Dock icon.
- Menu bar title shows CPU / SoC temperature when the helper can read it, otherwise `--°`.
- Native macOS status-item menu (`NSMenu`) so the opened menu uses the system menu bar style.
- Default `System Auto` mode.
- Manual presets: `Silent`, `Balanced`, `Cool`, `Max`.
- Manual linear RPM slider with throttled writes.
- First-launch `Launch MacFan at login?` prompt plus menu toggle.
- Bottom `Quit MacFan` button that asks the helper to restore System Auto before quitting.
- AppleSMC helper boundary with safe fallback.

## Important beta-system note

On the current macOS 26.5 beta machine, the helper can read AppleSMC fan and temperature keys when installed with the local installer. If AppleSMC is unavailable after a system update, the app safely displays `--°`, returns to `System Auto`, and disables fan controls instead of crashing or retrying aggressively.

That fallback is intentional: this project prioritizes low overhead and safe System Auto behavior over forcing private beta-system interfaces.

## Build and verify

The installed Command Line Tools expose Swift Testing from a nonstandard framework location, so use these commands in this environment:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --enable-swift-testing
```

In the Codex sandbox, add `--disable-sandbox`:

```bash
CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift test --disable-sandbox --enable-swift-testing

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift build --disable-sandbox --product MacFanApp

CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-module-cache \
SWIFT_MODULE_CACHE_PATH=$PWD/.build/swift-module-cache \
swift build --disable-sandbox --product MacFanHelper
```

Smoke-test the helper:

```bash
sudo ./.build/debug/MacFanHelper snapshot
```

Expected installed-helper output on the current target machine:

```text
temperature=31 currentRPM=0 minRPM=1199 maxRPM=7199 fanCount=1 modeKey=F0Md ftst=false control=true source=AppleSMC
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
