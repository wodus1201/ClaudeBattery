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
pkill -x ClaudeBattery 2>/dev/null || true
sleep 1
./build.sh

echo "==> 3/3  Restarting with the new binary"
if [ -f "$PLIST" ]; then
  # `kickstart -k` force-kills the current process and relaunches it from the
  # (freshly rebuilt) binary. This is reliable, unlike `launchctl load` which
  # silently no-ops when the service is already registered — that was why an
  # update rebuilt the code but the menu bar kept showing the old version.
  if launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>/dev/null; then
    :
  else
    # Service wasn't registered yet (e.g. first run) — register it now.
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
      || launchctl load -w "$PLIST" 2>/dev/null || true
  fi
else
  echo "    (LaunchAgent not found — run ./install.sh first for auto-start)"
fi

echo ""
echo "✅  Updated. The 클로드 widget is running the latest version."
