#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJ_ROOT/Vendor"
DIST_DIR="$PROJ_ROOT/dist"
APP_NAME="Bug On EXE.app"
LEGACY_APP_NAME="Bug On Mac exe.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"
LEGACY_INSTALL_PATH="/Applications/$LEGACY_APP_NAME"

mkdir -p "$VENDOR_DIR" "$DIST_DIR"

# Clean up legacy app bundle names if present
rm -rf "$DIST_DIR/$LEGACY_APP_NAME" "$LEGACY_INSTALL_PATH"

# 1. Obtain official 64-bit macOS Adobe Flash Player Projector 32 (Flash Player.app)
if [ ! -x "$VENDOR_DIR/Flash Player.app/Contents/MacOS/Flash Player" ]; then
    echo "==> Fetching Adobe Flash Player 32 Projector (64-bit macOS)..."
    DMG_PATH="$VENDOR_DIR/flashplayer_32_sa.dmg"
    URLS=(
        "https://web.archive.org/web/20201201000000id_/https://fpdownload.macromedia.com/pub/flashplayer/updaters/32/flashplayer_32_sa.dmg"
        "https://archive.org/download/adobe-flash-player-projector/flashplayer_32_sa.dmg"
        "https://archive.org/download/flashplayer_32_sa_202104/flashplayer_32_sa.dmg"
        "https://archive.org/download/macromedia-flash-player-projector-macos-x86-64/flashplayer_32_sa.dmg"
    )
    DOWNLOADED=0
    for url in "${URLS[@]}"; do
        echo "Trying $url ..."
        if curl -fL --connect-timeout 15 --max-time 120 -o "$DMG_PATH" "$url"; then
            if file "$DMG_PATH" | grep -qiE "disk image|zlib|bzip2|UDIF|HFS|Apple"; then
                DOWNLOADED=1
                break
            fi
        fi
    done

    if [ "$DOWNLOADED" -ne 1 ]; then
        echo "ERROR: Could not download flashplayer_32_sa.dmg from primary URLs" >&2
        exit 1
    fi

    MOUNT_POINT="$(mktemp -d /tmp/flash_dmg.XXXXXX)"
    hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_POINT" -nobrowse -readonly -quiet
    cp -R "$MOUNT_POINT/Flash Player.app" "$VENDOR_DIR/Flash Player.app"
    hdiutil detach "$MOUNT_POINT" -quiet || true
    rmdir "$MOUNT_POINT" || true
fi

echo "==> Verifying 64-bit Flash Player Projector architecture..."
file "$VENDOR_DIR/Flash Player.app/Contents/MacOS/Flash Player" | grep "Mach-O 64-bit executable x86_64"

# 2. Generate and Compile AppIcon (Adaptive for macOS 26+ and Legacy icns)
if [ -f "$PROJ_ROOT/gemini-svg.svg" ]; then
    echo "==> Generating AppIcon assets from gemini-svg.svg..."
    ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    swift "$PROJ_ROOT/scripts/generate_app_icon.swift" "$DIST_DIR" "$PROJ_ROOT"

    echo "==> Packaging AppIcon.icns for legacy macOS..."
    iconutil -c icns "$ICONSET_DIR" -o "$DIST_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
elif [ ! -f "$DIST_DIR/AppIcon.icns" ]; then
    ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    cp -R "$PROJ_ROOT/Resources/Assets.xcassets/AppIcon.appiconset/"* "$ICONSET_DIR/" 2>/dev/null || true
    iconutil -c icns "$ICONSET_DIR" -o "$DIST_DIR/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET_DIR"
fi

# 3. Assemble Bug On EXE.app bundle
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$PROJ_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp -R "$PROJ_ROOT/Resources/en.lproj" "$APP_BUNDLE/Contents/Resources/en.lproj"
cp -R "$PROJ_ROOT/Resources/vi.lproj" "$APP_BUNDLE/Contents/Resources/vi.lproj"
cp -R "$VENDOR_DIR/Flash Player.app" "$APP_BUNDLE/Contents/Resources/Flash Player.app"

echo "==> Compiling Asset Catalog (Assets.car) with actool for macOS 26+..."
xcrun actool "$PROJ_ROOT/Resources/Assets.xcassets" \
  --compile "$APP_BUNDLE/Contents/Resources" \
  --platform macosx \
  --target-device mac \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$DIST_DIR/assetcatalog_generated_info.plist"
rm -f "$DIST_DIR/assetcatalog_generated_info.plist"

# Copy full 10-resolution AppIcon.icns AFTER actool so it is not truncated
echo "==> Preserving full-resolution AppIcon.icns..."
cp "$DIST_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Verify compiled icon deliverables exist inside the bundle and has full assets (> 500KB)
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -f "$APP_BUNDLE/Contents/Resources/Assets.car"
ICNS_SIZE=$(stat -f%z "$APP_BUNDLE/Contents/Resources/AppIcon.icns")
[ "$ICNS_SIZE" -gt 500000 ] || { echo "ERROR: AppIcon.icns too small ($ICNS_SIZE bytes)"; exit 1; }

echo "==> Compiling BugOnMacExe binary (x86_64)..."
swiftc \
  -O \
  -target x86_64-apple-macosx13.0 \
  "$PROJ_ROOT/Sources/Core/LocalizationManager.swift" \
  "$PROJ_ROOT/Sources/Core/ExeSwfExtractor.swift" \
  "$PROJ_ROOT/Sources/Core/PortableExeExtractor.swift" \
  "$PROJ_ROOT/Sources/Core/WineRuntimeManager.swift" \
  "$PROJ_ROOT/Sources/Core/SessionManager.swift" \
  "$PROJ_ROOT/Sources/Core/DefaultAppManager.swift" \
  "$PROJ_ROOT/Sources/Core/ExeLibraryStore.swift" \
  "$PROJ_ROOT/Sources/App/WineInstallProgressWindowController.swift" \
  "$PROJ_ROOT/Sources/App/ProjectorRunner.swift" \
  "$PROJ_ROOT/Sources/App/LauncherCardGridView.swift" \
  "$PROJ_ROOT/Sources/App/LauncherWindowController.swift" \
  "$PROJ_ROOT/Sources/App/AppMenuManager.swift" \
  "$PROJ_ROOT/Sources/App/AppDelegate.swift" \
  "$PROJ_ROOT/Sources/App/main.swift" \
  -o "$APP_BUNDLE/Contents/MacOS/BugOnMacExe"

# 4. Strip quarantine and ad-hoc sign both inner runtime and outer bundle
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE/Contents/Resources/Flash Player.app"
codesign --force --deep --sign - "$APP_BUNDLE"

# 5. Install to /Applications and register with LaunchServices
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"
xattr -cr "$INSTALL_PATH"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$INSTALL_PATH"
fi

echo "==> Successfully built and installed: $INSTALL_PATH"
