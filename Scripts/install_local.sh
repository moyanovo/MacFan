#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/MacFan.app"
HELPER_IN_APP="$APP/Contents/Resources/MacFanHelper"
APP_DEST="/Applications/MacFan.app"
HELPER_DEST="/Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper"

if [[ ! -d "$APP" || ! -x "$HELPER_IN_APP" ]]; then
  "$ROOT/Scripts/package_app.sh" >/dev/null
fi

osascript <<OSA
set rootPath to POSIX path of "$ROOT"
set appPath to POSIX path of "$APP"
set helperPath to POSIX path of "$HELPER_IN_APP"
do shell script "rm -rf /Applications/MacFan.app && cp -R " & quoted form of appPath & " /Applications/MacFan.app && xattr -cr /Applications/MacFan.app && codesign --force --deep --sign - /Applications/MacFan.app && mkdir -p /Library/PrivilegedHelperTools && cp " & quoted form of helperPath & " /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper && chown root:wheel /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper && chmod 4755 /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper" with administrator privileges
OSA

open "$APP_DEST"
echo "Installed $APP_DEST"
echo "Installed $HELPER_DEST"
