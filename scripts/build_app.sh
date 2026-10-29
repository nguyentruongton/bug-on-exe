#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJ_ROOT/Vendor"
DIST_DIR="$PROJ_ROOT/dist"
APP_NAME="Bug On Mac exe.app"
APP_BUNDLE="$DIST_DIR/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

mkdir -p "$VENDOR_DIR" "$DIST_DIR"

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

# 2. Generate AppIcon.icns
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" << 'SWIFT_ICON'
import AppKit
import CoreGraphics

let iconsetPath = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    let inset = CGFloat(px) * 0.08
    let cardRect = rect.insetBy(dx: inset, dy: inset)
    let radius = CGFloat(px) * 0.22
    let path = NSBezierPath(roundedRect: cardRect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.78, green: 0.12, blue: 0.16, alpha: 1.0),
                              ending: NSColor(calibratedRed: 0.25, green: 0.04, blue: 0.08, alpha: 1.0))!
    gradient.draw(in: path, angle: -45)

    let pStyle = NSMutableParagraphStyle()
    pStyle.alignment = .center
    let fontSize = CGFloat(px) * 0.25
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: fontSize),
        .foregroundColor: NSColor.white,
        .paragraphStyle: pStyle
    ]
    let text = NSString(string: "EXE")
    let textRect = NSRect(x: 0, y: (CGFloat(px) - fontSize * 1.2) / 2.0, width: CGFloat(px), height: fontSize * 1.3)
    text.draw(in: textRect, withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    let outURL = URL(fileURLWithPath: iconsetPath).appendingPathComponent(name)
    try! pngData.write(to: outURL)
}
SWIFT_ICON

iconutil -c icns "$ICONSET_DIR" -o "$DIST_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# 3. Assemble Bug On Mac exe.app bundle
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$PROJ_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$DIST_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp -R "$PROJ_ROOT/Resources/en.lproj" "$APP_BUNDLE/Contents/Resources/en.lproj"
cp -R "$PROJ_ROOT/Resources/vi.lproj" "$APP_BUNDLE/Contents/Resources/vi.lproj"
cp -R "$VENDOR_DIR/Flash Player.app" "$APP_BUNDLE/Contents/Resources/Flash Player.app"

echo "==> Compiling BugOnMacExe binary (x86_64)..."
swiftc \
  -O \
  -target x86_64-apple-macosx13.0 \
  "$PROJ_ROOT/Sources/Core/LocalizationManager.swift" \
  "$PROJ_ROOT/Sources/Core/ExeSwfExtractor.swift" \
  "$PROJ_ROOT/Sources/Core/SessionManager.swift" \
  "$PROJ_ROOT/Sources/Core/DefaultAppManager.swift" \
  "$PROJ_ROOT/Sources/Core/ExeLibraryStore.swift" \
  "$PROJ_ROOT/Sources/App/ProjectorRunner.swift" \
  "$PROJ_ROOT/Sources/App/LauncherCardGridView.swift" \
  "$PROJ_ROOT/Sources/App/LauncherWindowController.swift" \
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
