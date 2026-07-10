#!/bin/bash
# Claude Battery — start (or restart) the widget after ./stop.sh.
set -euo pipefail
cd "$(dirname "$0")"

APP="$(pwd)/build/ClaudeBattery.app"
[ -d "$APP" ] || { echo "빌드가 없습니다 — 먼저 ./install.sh 를 실행하세요."; exit 1; }

pkill -x ClaudeBattery 2>/dev/null || true
sleep 0.3
open "$APP"
echo "✅  Started. Look for the 클로드 widget in the menu bar."
