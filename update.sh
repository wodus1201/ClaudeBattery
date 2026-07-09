#!/bin/bash
# Claude Battery — update to the latest version.
# Pulls the newest code, rebuilds for THIS machine, and restarts the widget.
# Run this on any machine that already installed via ./install.sh.
set -euo pipefail
cd "$(dirname "$0")"
LABEL="com.jay.ClaudeBattery"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

echo "==> 1/3  Pulling latest code"
git pull --ff-only

echo "==> 2/3  Rebuilding for this machine"
# Stop the running instance first so the app bundle isn't file-locked mid-build.
launchctl unload "$PLIST" 2>/dev/null || true
pkill -x ClaudeBattery 2>/dev/null || true
sleep 1
./build.sh

echo "==> 3/3  Restarting"
if [ -f "$PLIST" ]; then
  launchctl load -w "$PLIST"
else
  echo "    (LaunchAgent not found — run ./install.sh first for auto-start)"
fi

echo ""
echo "✅  Updated. The 클로드 widget is running the latest version."
