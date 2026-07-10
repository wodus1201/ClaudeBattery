#!/bin/bash
# Claude Battery — stop the widget.
#
# Auto-start now lives in SMAppService (the "로그인 시 자동 시작" menu toggle),
# not in a LaunchAgent, so nothing revives the app after this. The bootout is
# only here to quiet a leftover agent from a pre-1.1 install.
set -euo pipefail
LABEL="com.jay.ClaudeBattery"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -x ClaudeBattery 2>/dev/null || true
echo "✅  Stopped. Run ./start.sh to turn it back on."
