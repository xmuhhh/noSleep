#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/NoSleep.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/NoSleep" "$MACOS_DIR/NoSleep"
cp "packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "assets/app-icon/NoSleep.icns" "$RESOURCES_DIR/NoSleep.icns"
chmod +x "$MACOS_DIR/NoSleep"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
