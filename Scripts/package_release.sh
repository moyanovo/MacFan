#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="1.0.0"
DIST="$ROOT/dist"
APP="$DIST/MacFan.app"
RELEASE_DIR="$DIST/MacFan-v$VERSION"
ZIP="$DIST/MacFan-v$VERSION.zip"

"$ROOT/Scripts/package_app.sh" >/dev/null

rm -rf "$RELEASE_DIR" "$ZIP"
mkdir -p "$RELEASE_DIR"
COPYFILE_DISABLE=1 ditto --norsrc "$APP" "$RELEASE_DIR/MacFan.app"

cat > "$RELEASE_DIR/Install.command" <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/MacFan.app"
HELPER="$APP/Contents/Resources/MacFanHelper"

if [[ ! -d "$APP" || ! -x "$HELPER" ]]; then
  echo "MacFan.app or bundled MacFanHelper is missing."
  exit 1
fi

osascript <<OSA
set appPath to POSIX path of "$APP"
set helperPath to POSIX path of "$HELPER"
do shell script "pkill -x MacFanApp >/dev/null 2>&1 || true; rm -rf /Applications/MacFan.app && cp -R " & quoted form of appPath & " /Applications/MacFan.app && xattr -cr /Applications/MacFan.app && codesign --force --deep --sign - /Applications/MacFan.app && mkdir -p /Library/PrivilegedHelperTools && cp " & quoted form of helperPath & " /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper && chown root:wheel /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper && chmod 4755 /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper" with administrator privileges
OSA

open /Applications/MacFan.app
echo "Installed /Applications/MacFan.app"
echo "Installed /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper"
INSTALL

cat > "$RELEASE_DIR/Uninstall.command" <<'UNINSTALL'
#!/usr/bin/env bash
set -euo pipefail

osascript <<'OSA'
do shell script "pkill -x MacFanApp >/dev/null 2>&1 || true; /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper auto >/dev/null 2>&1 || true; rm -rf /Applications/MacFan.app /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper" with administrator privileges
OSA
rm -f "$HOME/Library/Preferences/com.moyanovo.MacFan.plist"
rm -f "$HOME"/Library/Logs/DiagnosticReports/Retired/MacFanApp-*.ips
echo "Uninstalled MacFan"
UNINSTALL

cat > "$RELEASE_DIR/README.txt" <<'README'
MacFan v1.0.0

Install:
1. Open this folder.
2. Double-click Install.command.
3. Approve the administrator prompt. The prompt is required to install the AppleSMC helper at /Library/PrivilegedHelperTools.

Uninstall:
Double-click Uninstall.command.

Note:
Running MacFan.app directly is safe, but full temperature/fan control may require Install.command because AppleSMC access needs the installed helper.
README

chmod +x "$RELEASE_DIR/Install.command" "$RELEASE_DIR/Uninstall.command"
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$RELEASE_DIR" >/dev/null 2>&1 || true
fi

(cd "$DIST" && COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "MacFan-v$VERSION" "MacFan-v$VERSION.zip")
shasum -a 256 "$ZIP"
