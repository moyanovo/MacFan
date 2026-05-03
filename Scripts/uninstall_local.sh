#!/usr/bin/env bash
set -euo pipefail
osascript <<'OSA'
do shell script "pkill -x MacFanApp >/dev/null 2>&1 || true; /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper auto >/dev/null 2>&1 || true; rm -rf /Applications/MacFan.app /Library/PrivilegedHelperTools/com.moyanovo.MacFanHelper" with administrator privileges
OSA
echo "Uninstalled MacFan"
