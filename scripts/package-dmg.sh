#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_RW="$DIST_DIR/NoSleep-rw.dmg"
DMG_FINAL="$DIST_DIR/NoSleep.dmg"
VOLUME_NAME="NoSleep"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/package-app.sh" >/dev/null

rm -rf "$STAGING_DIR" "$DMG_RW" "$DMG_FINAL"
mkdir -p "$STAGING_DIR"

ditto "$ROOT_DIR/build/NoSleep.app" "$STAGING_DIR/NoSleep.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/INSTALL.md" "$STAGING_DIR/INSTALL.md"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size 32m \
  "$DMG_RW" >/dev/null

MOUNT_OUTPUT="$(hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen)"
DEVICE="$(printf '%s\n' "$MOUNT_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
MOUNT_POINT="$(printf '%s\n' "$MOUNT_OUTPUT" | awk '/Apple_HFS/ {for (i=3; i<=NF; i++) {printf "%s%s", (i==3 ? "" : " "), $i}; print ""; exit}')"

if [[ -n "${MOUNT_POINT:-}" && -d "$MOUNT_POINT" ]]; then
  osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 640, 420}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set position of item "NoSleep.app" of container window to {150, 170}
    set position of item "Applications" of container window to {390, 170}
    set position of item "INSTALL.md" of container window to {270, 300}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT
fi

sync
hdiutil detach "$DEVICE" >/dev/null
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL" >/dev/null
rm -rf "$STAGING_DIR" "$DMG_RW"

echo "$DMG_FINAL"
