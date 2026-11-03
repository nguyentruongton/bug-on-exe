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

# 2. Generate Apple HIG Liquid Glass AppIcon.icns (Concept B: "Bug ON" Switch)
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" "$PROJ_ROOT/Resources/AppIcon-Preview.png" << 'SWIFT_ICON'
import AppKit
import CoreGraphics

let iconsetPath = CommandLine.arguments[1]
let previewPath = CommandLine.arguments[2]
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

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    return NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

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

    let s = CGFloat(px)
    // Clear transparent canvas
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // 1. Apple HIG macOS Squircle Grid (824x824 inside 1024x1024 -> 0.0976 inset)
    let inset = s * 0.0976
    let cardRect = NSRect(x: inset, y: inset, width: s - inset * 2.0, height: s - inset * 2.0)
    let cornerRadius = cardRect.width * 0.225
    let squirclePath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // macOS Dock Drop Shadow
    NSGraphicsContext.saveGraphicsState()
    let dockShadow = NSShadow()
    dockShadow.shadowOffset = NSSize(width: 0, height: -s * 0.026)
    dockShadow.shadowBlurRadius = s * 0.042
    dockShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.42)
    dockShadow.set()
    color(15, 23, 42).setFill()
    squirclePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Layer 1: Midnight Slate Squircle Background + Ambient Emerald Glow
    NSGraphicsContext.saveGraphicsState()
    squirclePath.addClip()
    let bgGrad = NSGradient(starting: color(15, 23, 42), ending: color(30, 41, 59))!
    bgGrad.draw(in: cardRect, angle: -90)

    let glowGrad = NSGradient(starting: color(16, 185, 129, 0.25), ending: color(15, 23, 42, 0.0))!
    glowGrad.draw(
        fromCenter: NSPoint(x: s * 0.50, y: s * 0.58),
        radius: 0,
        toCenter: NSPoint(x: s * 0.50, y: s * 0.58),
        radius: s * 0.42,
        options: []
    )

    // Subtle top glass sheen
    let sheenRect = NSRect(x: cardRect.minX, y: s * 0.52, width: cardRect.width, height: cardRect.height * 0.5)
    let sheenGrad = NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 0.10), ending: NSColor(calibratedWhite: 1.0, alpha: 0.0))!
    sheenGrad.draw(in: sheenRect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Specular outer rim on squircle
    let rimInset = max(0.5, s * 0.004)
    let rimPath = NSBezierPath(
        roundedRect: cardRect.insetBy(dx: rimInset, dy: rimInset),
        xRadius: cornerRadius - rimInset,
        yRadius: cornerRadius - rimInset
    )
    rimPath.lineWidth = max(1.0, s * 0.007)
    NSColor(calibratedWhite: 1.0, alpha: 0.28).setStroke()
    rimPath.stroke()

    // 2. Layer 2: Emerald Liquid Glass "ON" Switch Track
    let trackRect = NSRect(x: s * 0.19, y: s * 0.44, width: s * 0.62, height: s * 0.30)
    let trackRadius = trackRect.height * 0.5
    let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: trackRadius, yRadius: trackRadius)

    NSGraphicsContext.saveGraphicsState()
    let trackShadow = NSShadow()
    trackShadow.shadowOffset = NSSize(width: 0, height: -s * 0.014)
    trackShadow.shadowBlurRadius = s * 0.024
    trackShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.35)
    trackShadow.set()
    color(5, 150, 105).setFill()
    trackPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let trackGrad = NSGradient(starting: color(52, 211, 153), ending: color(5, 150, 105))!
    trackGrad.draw(in: trackPath, angle: -45)

    trackPath.lineWidth = max(1.0, s * 0.006)
    NSColor(calibratedWhite: 1.0, alpha: 0.45).setStroke()
    trackPath.stroke()

    // Draw "ON" text inside left side of switch track (skip at <= 32px per Apple HIG legibility)
    if px > 32 {
        let onStyle = NSMutableParagraphStyle()
        onStyle.alignment = .center
        let onFontSize = s * 0.080
        let onFont = NSFont.systemFont(ofSize: onFontSize, weight: .heavy)
        let onAttrs: [NSAttributedString.Key: Any] = [
            .font: onFont,
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.94),
            .paragraphStyle: onStyle
        ]
        let onText = NSString(string: "ON")
        let onSize = onText.size(withAttributes: onAttrs)
        let onRect = NSRect(
            x: s * 0.23,
            y: trackRect.midY - onSize.height * 0.5,
            width: s * 0.24,
            height: onSize.height
        )
        onText.draw(in: onRect, withAttributes: onAttrs)
    }

    // 3. Layer 3a: 3D Glass Knob with Ruby Glass Bug
    let knobCenter = NSPoint(x: s * 0.65, y: trackRect.midY)
    let kr = s * 0.124
    let knobRect = NSRect(x: knobCenter.x - kr, y: knobCenter.y - kr, width: kr * 2.0, height: kr * 2.0)
    let knobPath = NSBezierPath(ovalIn: knobRect)

    NSGraphicsContext.saveGraphicsState()
    let knobShadow = NSShadow()
    knobShadow.shadowOffset = NSSize(width: 0, height: -s * 0.010)
    knobShadow.shadowBlurRadius = s * 0.020
    knobShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.36)
    knobShadow.set()
    NSColor.white.setFill()
    knobPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let knobGrad = NSGradient(starting: color(255, 255, 255), ending: color(226, 232, 240))!
    knobGrad.draw(in: knobPath, angle: -90)

    // Stylized Bug inside Knob
    if px >= 32 {
        let antPath = NSBezierPath()
        antPath.lineWidth = max(1.0, s * 0.007)
        antPath.lineCapStyle = .round
        antPath.move(to: NSPoint(x: knobCenter.x - kr * 0.14, y: knobCenter.y + kr * 0.42))
        antPath.line(to: NSPoint(x: knobCenter.x - kr * 0.32, y: knobCenter.y + kr * 0.64))
        antPath.move(to: NSPoint(x: knobCenter.x + kr * 0.14, y: knobCenter.y + kr * 0.42))
        antPath.line(to: NSPoint(x: knobCenter.x + kr * 0.32, y: knobCenter.y + kr * 0.64))
        color(15, 23, 42).setStroke()
        antPath.stroke()
    }

    let headRadius = kr * 0.25
    let headRect = NSRect(
        x: knobCenter.x - headRadius,
        y: knobCenter.y + kr * 0.16,
        width: headRadius * 2.0,
        height: headRadius * 1.8
    )
    let headPath = NSBezierPath(ovalIn: headRect)
    color(15, 23, 42).setFill()
    headPath.fill()

    let bodyRx = kr * 0.46
    let bodyRy = kr * 0.52
    let bodyRect = NSRect(
        x: knobCenter.x - bodyRx,
        y: knobCenter.y - kr * 0.60,
        width: bodyRx * 2.0,
        height: bodyRy * 2.0
    )
    let bodyPath = NSBezierPath(ovalIn: bodyRect)
    let bugGrad = NSGradient(starting: color(255, 77, 109), ending: color(190, 18, 60))!
    bugGrad.draw(in: bodyPath, angle: -90)

    // Wing division line
    let seamPath = NSBezierPath()
    seamPath.lineWidth = max(1.0, s * 0.008)
    seamPath.move(to: NSPoint(x: knobCenter.x, y: bodyRect.maxY - kr * 0.04))
    seamPath.line(to: NSPoint(x: knobCenter.x, y: bodyRect.minY + kr * 0.04))
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
    seamPath.stroke()

    if px >= 64 {
        let spotR = kr * 0.08
        let leftSpot = NSBezierPath(ovalIn: NSRect(x: knobCenter.x - kr * 0.26 - spotR, y: knobCenter.y - kr * 0.12 - spotR, width: spotR * 2, height: spotR * 2))
        let rightSpot = NSBezierPath(ovalIn: NSRect(x: knobCenter.x + kr * 0.26 - spotR, y: knobCenter.y - kr * 0.12 - spotR, width: spotR * 2, height: spotR * 2))
        NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
        leftSpot.fill()
        rightSpot.fill()
    }

    // 4. Layer 3b: Frosted Liquid Glass ".EXE" Pill
    let pillRect = NSRect(x: s * 0.24, y: s * 0.17, width: s * 0.52, height: s * 0.16)
    let pillRadius = s * 0.052
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRadius, yRadius: pillRadius)

    let pillGrad = NSGradient(
        starting: NSColor(calibratedWhite: 1.0, alpha: 0.20),
        ending: NSColor(calibratedWhite: 1.0, alpha: 0.08)
    )!
    pillGrad.draw(in: pillPath, angle: -90)

    pillPath.lineWidth = max(1.0, s * 0.006)
    NSColor(calibratedWhite: 1.0, alpha: 0.38).setStroke()
    pillPath.stroke()

    let exeStyle = NSMutableParagraphStyle()
    exeStyle.alignment = .center
    let exeFontSize = s * 0.088
    let exeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: exeFontSize),
        .foregroundColor: color(56, 189, 248),
        .paragraphStyle: exeStyle,
        .kern: s * 0.008
    ]
    let exeText = NSString(string: ".EXE")
    let exeSize = exeText.size(withAttributes: exeAttrs)
    let exeRect = NSRect(
        x: pillRect.minX,
        y: pillRect.midY - exeSize.height * 0.5,
        width: pillRect.width,
        height: exeSize.height
    )
    exeText.draw(in: exeRect, withAttributes: exeAttrs)

    NSGraphicsContext.restoreGraphicsState()

    let pngData = rep.representation(using: .png, properties: [:])!
    let outURL = URL(fileURLWithPath: iconsetPath).appendingPathComponent(name)
    try! pngData.write(to: outURL)

    if name == "icon_256x256@2x.png" {
        try! pngData.write(to: URL(fileURLWithPath: previewPath))
    }
}
SWIFT_ICON

iconutil -c icns "$ICONSET_DIR" -o "$DIST_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# 3. Assemble Bug On EXE.app bundle
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
  "$PROJ_ROOT/Sources/Core/PortableExeExtractor.swift" \
  "$PROJ_ROOT/Sources/Core/WineRuntimeManager.swift" \
  "$PROJ_ROOT/Sources/Core/SessionManager.swift" \
  "$PROJ_ROOT/Sources/Core/DefaultAppManager.swift" \
  "$PROJ_ROOT/Sources/Core/ExeLibraryStore.swift" \
  "$PROJ_ROOT/Sources/App/WineInstallProgressWindowController.swift" \
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
