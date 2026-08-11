#!/bin/bash
# Package dist/Vimkin.app into a drag-to-install DMG.
# Adapted from the vimhint release pipeline (MIT).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.0.0}"
APP="$REPO_ROOT/dist/Vimkin.app"
DMG="$REPO_ROOT/dist/vimkin-${VERSION}.dmg"

[ -d "$APP" ] || { echo "error: $APP not found — run scripts/make-app.sh first" >&2; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "Vimkin" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"

echo "Created $DMG"
