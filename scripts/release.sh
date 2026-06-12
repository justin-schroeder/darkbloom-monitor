#!/bin/bash
# Cuts a release: bumps the version, tags it, and pushes — GitHub Actions
# takes it from there (build, sign, package .dmg, publish the Release).
#
# Usage:
#   scripts/release.sh patch        # 1.2.3 → 1.2.4 (default)
#   scripts/release.sh minor        # 1.2.3 → 1.3.0
#   scripts/release.sh major        # 1.2.3 → 2.0.0
#   scripts/release.sh 1.4.0        # explicit version
set -euo pipefail
cd "$(dirname "$0")/.."

BUMP="${1:-patch}"

# Preflight: clean tree (tracked files), on main, up to date, tests green.
[ -z "$(git status --porcelain -uno)" ] || { echo "error: working tree has uncommitted changes" >&2; exit 1; }
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || { echo "error: release from main (on $BRANCH)" >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || {
    echo "error: local main is not in sync with origin/main" >&2; exit 1; }

echo "▸ running tests"
swift test -q

# Next version from the latest v* tag.
LATEST=$(git tag -l 'v*' --sort=-v:refname | head -1)
LATEST="${LATEST#v}"
LATEST="${LATEST:-0.0.0}"
IFS=. read -r MAJ MIN PAT <<< "$LATEST"
case "$BUMP" in
    major) VERSION="$((MAJ + 1)).0.0" ;;
    minor) VERSION="$MAJ.$((MIN + 1)).0" ;;
    patch) VERSION="$MAJ.$MIN.$((PAT + 1))" ;;
    [0-9]*.[0-9]*.[0-9]*) VERSION="$BUMP" ;;
    *) echo "error: expected major|minor|patch or X.Y.Z, got '$BUMP'" >&2; exit 1 ;;
esac
TAG="v$VERSION"
git rev-parse "$TAG" >/dev/null 2>&1 && { echo "error: $TAG already exists" >&2; exit 1; }

echo "▸ releasing $TAG (was v$LATEST)"
plutil -replace CFBundleShortVersionString -string "$VERSION" Resources/Info.plist
if ! git diff --quiet Resources/Info.plist; then
    git add Resources/Info.plist
    git commit -m "chore(release): $TAG"
fi
git tag -a "$TAG" -m "Release $TAG"
git push origin main "$TAG"

echo "✓ pushed $TAG — release workflow: $(gh repo view --json url -q .url 2>/dev/null || echo '<repo>')/actions"
