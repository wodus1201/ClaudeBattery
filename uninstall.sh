#!/bin/bash
# Claude Battery — remove the auto-start login item and stop the app.
set -euo pipefail
LABEL="com.jay.ClaudeBattery"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl unload -w "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -x ClaudeBattery 2>/dev/null || true

echo "✅  Uninstalled (login item removed, app stopped)."
echo "    The source folder is untouched — delete it manually if you want."
