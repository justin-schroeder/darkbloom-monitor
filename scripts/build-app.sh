#!/bin/bash
# Builds Darkbloom Monitor.app into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Darkbloom Monitor.app"

echo "▸ swift build -c release"
swift build -c release

echo "▸ assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DarkbloomMenu "$APP/Contents/MacOS/DarkbloomMenu"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ rendering icon"
ICON_TMP=$(mktemp -d)
swift scripts/make-icon.swift "$ICON_TMP"
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

echo "▸ codesign (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "▸ zip for distribution"
ditto -c -k --keepParent "$APP" "dist/Darkbloom-Monitor.zip"

echo "✓ built: $APP"
