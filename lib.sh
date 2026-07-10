#!/bin/bash
# Claude Battery — shared helpers used by install.sh / update.sh.
# Not meant to be run directly; sourced by the other scripts.

# Auto-start is owned by the app (SMAppService, via the "로그인 시 자동 시작"
# menu toggle). LABEL/PLIST survive only so the scripts can retire a LaunchAgent
# left behind by a pre-1.1 install.
LABEL="com.jay.ClaudeBattery"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

# Put a clickable alias in /Applications so the app shows up in Launchpad /
# Spotlight and can be double-clicked to launch, without moving the source.
link_to_applications() {
  local app="$1"
  local dest="/Applications/ClaudeBattery.app"
  # Remove a stale link/copy, then symlink the real bundle.
  if [ -L "$dest" ] || [ -e "$dest" ]; then rm -rf "$dest" 2>/dev/null || true; fi
  ln -s "$app" "$dest" 2>/dev/null \
    && echo "    Linked into /Applications (Launchpad/Spotlight에서 'ClaudeBattery' 검색 가능)" \
    || echo "    (/Applications 링크 생략 — 권한 문제 시 수동으로 앱을 드래그하세요)"
}
