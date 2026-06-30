#!/bin/bash
# Builds Darkbloom Monitor.app into dist/.
#
# Env:
#   VERSION        – marketing version to stamp into Info.plist (default: latest
#                    v* git tag without the v, falling back to 0.0.0-dev)
#   SIGN_IDENTITY  – codesign identity (default "-" for ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Darkbloom Monitor.app"
VERSION="${VERSION:-$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.0.0-dev}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "▸ swift build -c release (version ${VERSION})"
swift build -c release

echo "▸ assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/Helpers"
cp .build/release/DarkbloomMenu "$APP/Contents/MacOS/DarkbloomMenu"
cp .build/release/DarkbloomFanHelper "$APP/Contents/Library/Helpers/DarkbloomFanHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${GITHUB_RUN_NUMBER:-1}" "$APP/Contents/Info.plist"

echo "▸ rendering icon"
ICON_TMP=$(mktemp -d)
swift scripts/make-icon.swift "$ICON_TMP"
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

echo "▸ codesign (${SIGN_IDENTITY})"
CODESIGN_ARGS=(--force --deep --options runtime --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then
    CODESIGN_ARGS+=(--timestamp)
fi
codesign "${CODESIGN_ARGS[@]}" "$APP/Contents/Library/Helpers/DarkbloomFanHelper"
codesign "${CODESIGN_ARGS[@]}" "$APP"

echo "✓ built: $APP (v${VERSION})"
