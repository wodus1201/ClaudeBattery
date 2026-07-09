#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClaudeBattery.app"
BIN="$APP/Contents/MacOS/ClaudeBattery"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Info.plist — LSUIElement=1 makes it a menu-bar-only agent (no dock icon).
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>ClaudeBattery</string>
    <key>CFBundleDisplayName</key>     <string>Claude Battery</string>
    <key>CFBundleIdentifier</key>      <string>com.jay.ClaudeBattery</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>ClaudeBattery</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "Compiling…"
swiftc -O src/main.swift -o "$BIN"
chmod +x "$BIN"

# Bundle the pixel font (NeoDunggeunmo) so the app is self-contained.
mkdir -p "$APP/Contents/Resources"
cp fonts/neodgm.ttf "$APP/Contents/Resources/neodgm.ttf"

# Ad-hoc code signature so macOS lets it run without Gatekeeper nagging.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built: $APP"
