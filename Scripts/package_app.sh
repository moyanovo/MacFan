#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CLANG_MODULE_CACHE_PATH="$ROOT/.build/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT/.build/swift-module-cache"

swift build --disable-sandbox -c release

DIST="$ROOT/dist"
APP="$DIST/MacFan.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$ROOT/.build/release/MacFanApp" "$APP/Contents/MacOS/MacFanApp"
cp "$ROOT/.build/release/MacFanHelper" "$APP/Contents/Resources/MacFanHelper"
chmod 755 "$APP/Contents/MacOS/MacFanApp" "$APP/Contents/Resources/MacFanHelper"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacFanApp</string>
  <key>CFBundleIdentifier</key>
  <string>com.moyanovo.MacFan</string>
  <key>CFBundleName</key>
  <string>MacFan</string>
  <key>CFBundleDisplayName</key>
  <string>MacFan</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.1</string>
  <key>CFBundleVersion</key>
  <string>101</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP" >/dev/null 2>&1 || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" >/dev/null
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP" >/dev/null 2>&1 || true
fi

echo "$APP"
