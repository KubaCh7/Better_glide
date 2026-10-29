#!/bin/bash
# Packs BetterGlide.app into a drag-to-install disk image:
# the window shows the app next to a shortcut to /Applications.
#
# Usage: scripts/make-dmg.sh path/to/BetterGlide.app output.dmg
set -euo pipefail

APP="$1"
OUT="$2"
NAME="BetterGlide"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUT"
hdiutil create \
  -volname "$NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$OUT"

echo "Created $OUT"
