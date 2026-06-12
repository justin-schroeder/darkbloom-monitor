#!/bin/bash
# Packages dist/Darkbloom Monitor.app into a drag-to-Applications .dmg.
# Usage: scripts/make-dmg.sh [output.dmg]
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Darkbloom Monitor.app"
OUT="${1:-dist/Darkbloom-Monitor.dmg}"
[ -d "$APP" ] || { echo "error: $APP not found — run scripts/build-app.sh first" >&2; exit 1; }

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUT"
hdiutil create -volname "Darkbloom Monitor" -srcfolder "$STAGING" -ov -format UDZO -quiet "$OUT"
echo "✓ packaged: $OUT"
