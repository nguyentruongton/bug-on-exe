#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJ_ROOT/dist"
APP_NAME="Bug On EXE.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/Bug-On-EXE-macOS.zip"
DMG_PATH="$DIST_DIR/Bug-On-EXE-macOS.dmg"

if [ "${SKIP_BUILD:-0}" != "1" ] || [ ! -d "$APP_BUNDLE" ]; then
    bash "$SCRIPT_DIR/build_app.sh"
fi

echo "==> Packaging $ZIP_PATH (preserving executable permissions and code signatures)..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Packaging $DMG_PATH (with /Applications drag-and-drop symlink)..."
rm -f "$DMG_PATH"
STAGE_DIR="$(mktemp -d /tmp/bugonexe_dmg.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$APP_BUNDLE" "$STAGE_DIR/$APP_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "Bug On EXE" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "==> Release artifacts ready:"
ls -lh "$ZIP_PATH" "$DMG_PATH"
