#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/NoSleep"
ZIP_PATH="$DIST_DIR/NoSleep.zip"

cd "$ROOT_DIR"
"$ROOT_DIR/scripts/package-app.sh" >/dev/null

rm -rf "$PACKAGE_DIR" "$ZIP_PATH"
mkdir -p "$PACKAGE_DIR"
ditto "$ROOT_DIR/build/NoSleep.app" "$PACKAGE_DIR/NoSleep.app"
cp "$ROOT_DIR/INSTALL.md" "$PACKAGE_DIR/INSTALL.md"

cd "$DIST_DIR"
/usr/bin/zip -qry -X "$ZIP_PATH" "NoSleep"

echo "$ZIP_PATH"
