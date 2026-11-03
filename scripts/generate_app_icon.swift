import AppKit
import WebKit

// Parse command line arguments
let distDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dist"
let projRoot = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "."

let svgPath = (projRoot as NSString).appendingPathComponent("gemini-svg.svg")
let iconsetDir = (distDir as NSString).appendingPathComponent("AppIcon.iconset")
let xcassetsDir = (projRoot as NSString).appendingPathComponent("Resources/Assets.xcassets")
let appiconsetDir = (xcassetsDir as NSString).appendingPathComponent("AppIcon.appiconset")
let previewPath = (projRoot as NSString).appendingPathComponent("Resources/AppIcon-Preview.png")

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
try? fm.createDirectory(atPath: appiconsetDir, withIntermediateDirectories: true)

// 1. Render SVG via WebKit for full filter (<feMerge>, glow, dropShadow) support
print("==> Rendering gemini-svg.svg via WebKit...")
guard let svgContent = try? String(contentsOfFile: svgPath, encoding: .utf8) else {
    fatalError("Failed to read SVG file at \(svgPath)")
}

let canvasSize: CGFloat = 1024
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize))
webView.setValue(false, forKey: "drawsBackground")

let html = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
  * { box-sizing: border-box; }
  body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
  svg { width: 1024px; height: 1024px; display: block; }
</style>
</head>
<body>
\(svgContent)
</body>
</html>
"""

webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: projRoot))

while webView.isLoading {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}
// Allow layout & filter rendering
RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.25))

var renderedRawImage: NSImage?
var snapshotDone = false
let config = WKSnapshotConfiguration()
config.rect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

webView.takeSnapshot(with: config) { img, err in
    if let error = err {
        print("Snapshot error: \(error)")
    }
    renderedRawImage = img
    snapshotDone = true
}

while !snapshotDone {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
}

guard let mascotImage = renderedRawImage else {
    fatalError("Failed to capture snapshot from WebKit")
}

print("==> Successfully rendered SVG to transparent raster (\(mascotImage.size.width)x\(mascotImage.size.height))")

// Helper: Color shorthand
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> NSColor {
    return NSColor(calibratedRed: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
}

// 2. Generate macOS Squircle Icon (Light or Dark Background)
func drawMacIcon(size: Int, isDark: Bool = true) -> NSImage {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError() }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // Clear background
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // Apple macOS Squircle Grid (824x824 inside 1024x1024 -> inset ratio: 100/1024 = 0.09765)
    let inset = s * 0.09765
    let cardRect = NSRect(x: inset, y: inset, width: s - inset * 2.0, height: s - inset * 2.0)
    let cornerRadius = cardRect.width * 0.225
    let squirclePath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // 2.1. Bottom Soft Drop Shadow
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -s * 0.024),
        blur: s * 0.038,
        color: color(0, 0, 0, isDark ? 0.55 : 0.25).cgColor
    )
    if isDark {
        color(10, 15, 26, 1.0).setFill()
    } else {
        color(226, 232, 240, 1.0).setFill()
    }
    squirclePath.fill()
    cg.restoreGState()

    // 2.2. Base Squircle Gradient
    cg.saveGState()
    squirclePath.addClip()

    if isDark {
        // Obsidian Dark (#181E2C -> #0D111A -> #04070D)
        let bgGrad = NSGradient(colorsAndLocations:
            (color(24, 30, 44), 0.0),    // Top subtle slate-dark
            (color(13, 17, 26), 0.45),   // Mid obsidian
            (color(4, 7, 13), 1.0)       // Bottom pitch black
        )!
        bgGrad.draw(in: cardRect, angle: -90)

        // Subtle Radial Glow behind rocket
        let glowCenter = CGPoint(x: cardRect.midX + cardRect.width * 0.1, y: cardRect.midY + cardRect.height * 0.1)
        let glowColors = [color(56, 189, 248, 0.15).cgColor, color(249, 115, 22, 0.08).cgColor, color(0, 0, 0, 0).cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let radialGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
            cg.drawRadialGradient(radialGrad, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: cardRect.width * 0.55, options: [])
        }

        // Specular Rim Highlight (Dark Glass Edge)
        cg.saveGState()
        squirclePath.lineWidth = max(1.0, s * 0.0035)
        color(255, 255, 255, 0.28).setStroke()
        squirclePath.stroke()
        cg.restoreGState()
    } else {
        // Ceramic Light Metallic (#FFFFFF -> #F1F5F9 -> #E2E8F0)
        let bgGrad = NSGradient(colorsAndLocations:
            (color(255, 255, 255), 0.0),  // Pure white top reflection
            (color(241, 245, 249), 0.5),  // Soft off-white
            (color(226, 232, 240), 1.0)   // Cool silver-gray bottom
        )!
        bgGrad.draw(in: cardRect, angle: -90)

        // Subtle Radial Glow behind rocket
        let glowCenter = CGPoint(x: cardRect.midX + cardRect.width * 0.1, y: cardRect.midY + cardRect.height * 0.1)
        let glowColors = [color(56, 189, 248, 0.12).cgColor, color(249, 115, 22, 0.06).cgColor, color(255, 255, 255, 0).cgColor] as CFArray
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let radialGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.5, 1.0]) {
            cg.drawRadialGradient(radialGrad, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: cardRect.width * 0.55, options: [])
        }

        // Specular Rim Highlight (Crisp metallic edge)
        cg.saveGState()
        squirclePath.lineWidth = max(1.0, s * 0.0035)
        color(148, 163, 184, 0.45).setStroke()
        squirclePath.stroke()
        cg.restoreGState()
    }

    // Restore clip state so mascot drop shadow/glow is not clipped
    cg.restoreGState()

    // 2.3. Draw Mascot Graphic Centered and Scaled (~83.5% to respect Safe Area)
    let scaleRatio: CGFloat = 0.835
    let mascotW = s * scaleRatio
    let mascotH = s * scaleRatio
    // Fine-tune offset so the center of visual mass aligns with the card center
    let mascotX = (s - mascotW) / 2.0 + s * 0.012
    let mascotY = (s - mascotH) / 2.0 - s * 0.008
    let mascotRect = NSRect(x: mascotX, y: mascotY, width: mascotW, height: mascotH)

    mascotImage.draw(in: mascotRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    let finalImg = NSImage(size: NSSize(width: s, height: s))
    finalImg.addRepresentation(rep)
    return finalImg
}

// 3. Write all required iconset sizes for legacy icns
let iconsetSizes: [(Int, String)] = [
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

print("==> Generating AppIcon.iconset files...")
for (px, name) in iconsetSizes {
    let img = drawMacIcon(size: px)
    guard let rep = img.representations.first as? NSBitmapImageRep,
          let pngData = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG for \(name)")
    }
    let fileURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent(name)
    try! pngData.write(to: fileURL)

    // Copy the 512x512 icon for preview
    if name == "icon_256x256@2x.png" {
        try! pngData.write(to: URL(fileURLWithPath: previewPath))
    }
}

// 4. Generate Asset Catalog for macOS (AppIcon.appiconset + Adaptive AppIconImage.imageset)
print("==> Generating Asset Catalog (AppIcon.appiconset & AppIconImage.imageset)...")
for (_, name) in iconsetSizes {
    let srcURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent(name)
    let dstURL = URL(fileURLWithPath: appiconsetDir).appendingPathComponent(name)
    try? fm.removeItem(at: dstURL)
    try! fm.copyItem(at: srcURL, to: dstURL)
}

let assetCatalogJson = """
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16@2x.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32@2x.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128@2x.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256@2x.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512@2x.png", "scale" : "2x" }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""

try! assetCatalogJson.write(
    to: URL(fileURLWithPath: appiconsetDir).appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

// 4.2. Create Adaptive Imageset (AppIconImage.imageset) with Light & Dark luminosity appearances
let imagesetDir = (xcassetsDir as NSString).appendingPathComponent("AppIconImage.imageset")
try? fm.createDirectory(atPath: imagesetDir, withIntermediateDirectories: true)

let lightImg = drawMacIcon(size: 1024, isDark: false)
let darkImg = drawMacIcon(size: 1024, isDark: true)

if let lightRep = lightImg.representations.first as? NSBitmapImageRep,
   let lightData = lightRep.representation(using: .png, properties: [:]) {
    try! lightData.write(to: URL(fileURLWithPath: imagesetDir).appendingPathComponent("icon_light.png"))
    // Save preview for light mode
    let lightPreviewURL = URL(fileURLWithPath: (projRoot as NSString).appendingPathComponent("Resources/AppIcon-Preview-Light.png"))
    try! lightData.write(to: lightPreviewURL)
}

if let darkRep = darkImg.representations.first as? NSBitmapImageRep,
   let darkData = darkRep.representation(using: .png, properties: [:]) {
    try! darkData.write(to: URL(fileURLWithPath: imagesetDir).appendingPathComponent("icon_dark.png"))
}

let imagesetJson = """
{
  "images" : [
    {
      "idiom" : "universal",
      "filename" : "icon_light.png",
      "scale" : "1x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "idiom" : "universal",
      "filename" : "icon_dark.png",
      "scale" : "1x"
    }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""

try! imagesetJson.write(
    to: URL(fileURLWithPath: imagesetDir).appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

let rootCatalogJson = """
{
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""

try! rootCatalogJson.write(
    to: URL(fileURLWithPath: xcassetsDir).appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("==> Icon generation completed successfully!")
