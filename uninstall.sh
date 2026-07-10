#!/bin/bash
# Claude Battery — stop the app and remove auto-start.
set -euo pipefail
LABEL="com.jay.ClaudeBattery"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Pre-1.1 installs used a LaunchAgent; remove it if it's still around.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || launchctl unload -w "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
pkill -x ClaudeBattery 2>/dev/null || true

# The /Applications entry is a symlink for source installs, a real bundle for
# release installs. Removing either is safe; the source folder is untouched.
rm -rf /Applications/ClaudeBattery.app 2>/dev/null || true

echo "✅  Uninstalled (app stopped, /Applications entry removed)."
echo ""
echo "    자동 시작(로그인 항목)이 남아 있다면 한 번만 정리해 주세요:"
echo "    시스템 설정 → 일반 → 로그인 항목 → ClaudeBattery 제거"
echo "    (앱이 이미 삭제되어 SMAppService 등록을 코드로 해제할 수 없습니다.)"
echo ""
echo "    The source folder is untouched — delete it manually if you want."
