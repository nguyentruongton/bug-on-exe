# Bug On EXE Rebrand, Apple HIG App Icon & GitHub Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand the entire macOS utility from `"Bug On Mac exe"` to `"Bug On EXE"`, replace its app icon with the Apple HIG Liquid Glass **"Bug ON" Switch (Mẫu B)** design, and package ready-to-run `.dmg` and `.zip` release artifacts with bilingual documentation and GitHub Actions automation.

**Architecture:** Synchronize all display strings (`LocalizationManager.swift`, `en.lproj`, `vi.lproj`), bundle metadata (`Info.plist`), and runtime fallback paths (`ProjectorRunner.swift`) to `"Bug On EXE"` (`Bug On EXE.app`). Upgrade the CoreGraphics icon generator in `scripts/build_app.sh` to draw the 3-layer Liquid Glass "Bug ON" Switch inside a continuous-curvature macOS squircle with standard Dock drop shadow across all 10 Retina sizes, plus a `512×512` `Resources/AppIcon-Preview.png` for GitHub. Add `scripts/package_release.sh` to produce verified `dist/Bug-On-EXE-macOS.zip` (via `ditto`) and `dist/Bug-On-EXE-macOS.dmg` (via `hdiutil` with `/Applications` symlink), accompanied by `README.md` and `.github/workflows/release.yml`.

**Tech Stack:** Swift 6.3 (`swiftc`), AppKit / CoreGraphics, `iconutil`, `codesign`, `ditto`, `hdiutil`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-29-rebrand-bug-on-exe-and-release-design.md`

## Global Constraints

- App bundle name and display name must be `"Bug On EXE"` (`Bug On EXE.app` in `dist/` and `/Applications/`).
- Keep `CFBundleIdentifier` (`com.stark.bugonmacexe`) and `CFBundleExecutable` (`BugOnMacExe`) unchanged so existing LaunchServices `.exe` handler registrations and user library storage remain intact.
- Remove any legacy `/Applications/Bug On Mac exe.app` bundle during `scripts/build_app.sh` so Finder's "Open With" menu never lists duplicate apps.
- App Icon must follow Apple HIG macOS proportions (`824×824` squircle inside a `1024×1024` canvas, ~`9.76%` outer margin, bottom drop shadow, transparent outer corners) and omit small `"ON"` label text at `px <= 32`.
- Release `.zip` packaging must use `ditto -c -k --sequesterRsrc --keepParent` (never plain `zip`) so executable bits, resource forks, and ad-hoc code signatures inside `Bug On EXE.app` and `Flash Player.app` survive extraction.

## Review Focus

1. **Leftover legacy brand strings (`"Bug On Mac exe"`):** Any key in `LocalizationManager` (`en` or `vi`) or `Resources/*.lproj/Localizable.strings` still returning `"Bug On Mac exe"` instead of `"Bug On EXE"` — pinned in Task 1 (`test_localization.swift`).
2. **Duplicate app bundles in `/Applications`:** Leaving `/Applications/Bug On Mac exe.app` behind after installing `/Applications/Bug On EXE.app` causes Finder to show two `.exe` handlers — pinned in Task 2 (`test_bundle.swift`).
3. **Unmasked full-bleed icon canvas:** Drawing edge-to-edge on `1024×1024` without transparent outer corners violates Apple HIG squircle proportions — pinned in Task 2 (`test_bundle.swift` alpha-corner check on `Resources/AppIcon-Preview.png`).
4. **Corrupted `.strings` plist syntax:** Missing semicolons or unescaped quotes in `en.lproj/Localizable.strings` or `vi.lproj/Localizable.strings` silently breaks bundle localization — pinned in Task 2 (`test_bundle.swift` `PropertyListSerialization` parse check).
5. **Broken signature or executable bit after `.zip` extraction:** Archiving `.app` with standard tools strips executable permissions or breaks `codesign --verify --deep --strict` — pinned in Task 3 (`test_release_package.swift`).

---

### Task 1: Rebrand Display Strings, Bundle Metadata & Runtime Lookup to "Bug On EXE"

**Files:**
- Modify: `Sources/Core/LocalizationManager.swift:133-240`
- Modify: `Resources/en.lproj/Localizable.strings:1-46`
- Modify: `Resources/vi.lproj/Localizable.strings:1-46`
- Modify: `Resources/Info.plist:12-24`
- Modify: `Sources/App/ProjectorRunner.swift:66-70`
- Modify: `Tests/test_localization.swift:10-46`
- Modify: `Tests/test_fallback_routing.swift:24-35`

**Interfaces:**
- Consumes: `LocalizationManager.shared`, `L10nKey`, `LauncherWindowController`
- Produces:
  - `LocalizationManager.string(.windowTitleManager) == "Bug On EXE"` (in both `.english` and `.vietnamese`)
  - `LocalizationManager.string(.fallbackTitle) == "Bug On EXE"` (in both `.english` and `.vietnamese`)
  - `Info.plist` `CFBundleName == "Bug On EXE"` and `CFBundleDisplayName == "Bug On EXE"`
  - `ProjectorRunner.locateProjectorApp()` fallback path `/Applications/Bug On EXE.app/Contents/Resources/Flash Player.app`

- [ ] **Step 1: Update `Tests/test_localization.swift` and `Tests/test_fallback_routing.swift` with failing brand assertions**

In `Tests/test_localization.swift`, add assertions inside `main()` before the final `print`:

```swift
assert(manager.string(.windowTitleManager) == "Bug On EXE")
assert(manager.string(.fallbackTitle) == "Bug On EXE")
for lang in AppLanguage.allCases {
    manager.language = lang
    for key in L10nKey.allCases {
        let val = manager.string(key)
        assert(!val.isEmpty && val != key.rawValue, "Missing translation for \(key.rawValue) in \(lang.rawValue)")
        assert(!val.contains("Bug On Mac exe"), "Legacy brand name found in \(key.rawValue) (\(lang.rawValue)): \(val)")
    }
}
```

In `Tests/test_fallback_routing.swift:27`, update the window title assertion:

```swift
assert(controller.window?.title == "Bug On EXE")
```

- [ ] **Step 2: Run the localization and fallback routing tests to verify they fail**

Run:
```bash
swiftc Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization && /tmp/test_localization
```
Expected: FAIL with assertion failed on `windowTitleManager == "Bug On EXE"`.

- [ ] **Step 3: Update `Sources/Core/LocalizationManager.swift`, `Resources/*.lproj/Localizable.strings`, `Resources/Info.plist`, and `Sources/App/ProjectorRunner.swift`**

Replace every occurrence of `"Bug On Mac exe"` with `"Bug On EXE"` in:
- `Sources/Core/LocalizationManager.swift` (`englishTable` and `vietnameseTable`: `.windowTitleManager`, `.alertDefaultSetSuccessMessage`, `.alertDefaultSetConfirmMessage`, `.fallbackTitle`)
- `Resources/en.lproj/Localizable.strings` (`window.title.manager`, `alert.default_set.success_message`, `alert.default_set.confirm_message`, `fallback.title`)
- `Resources/vi.lproj/Localizable.strings` (`window.title.manager`, `alert.default_set.confirm_message`, `fallback.title`)
- `Resources/Info.plist` (`CFBundleDisplayName` and `CFBundleName`)
- `Sources/App/ProjectorRunner.swift:67` (`/Applications/Bug On EXE.app/Contents/Resources/Flash Player.app`)

- [ ] **Step 4: Run `test_localization` and `test_fallback_routing` to verify they pass**

Run:
```bash
swiftc Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization && /tmp/test_localization && \
swiftc Sources/Core/*.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Tests/test_fallback_routing.swift -o /tmp/test_fallback_routing && /tmp/test_fallback_routing
```
Expected: PASS (`ALL LOCALIZATION TESTS PASSED` and `All Fallback routing tests passed successfully!`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/LocalizationManager.swift Resources/en.lproj/Localizable.strings Resources/vi.lproj/Localizable.strings Resources/Info.plist Sources/App/ProjectorRunner.swift Tests/test_localization.swift Tests/test_fallback_routing.swift
git commit -m "feat(rebrand): rename application display strings and metadata to Bug On EXE"
```

---

### Task 2: Apple HIG Liquid Glass App Icon (Mẫu B: "Bug ON" Switch) & Bundle Assembly (`Bug On EXE.app`)

**Files:**
- Modify: `scripts/build_app.sh:8-161`
- Create: `Resources/AppIcon-Preview.png` (generated by `scripts/build_app.sh`)
- Modify: `Tests/test_bundle.swift:1-32`

**Interfaces:**
- Consumes: Updated `Resources/Info.plist`, `Resources/*.lproj/Localizable.strings`, `Sources/**/*.swift` from Task 1
- Produces:
  - `/Applications/Bug On EXE.app` and `dist/Bug On EXE.app`
  - `dist/AppIcon.icns` and `Resources/AppIcon-Preview.png` (`512×512` PNG)
  - Removal of `/Applications/Bug On Mac exe.app`

- [ ] **Step 1: Update `Tests/test_bundle.swift` with assertions for `Bug On EXE.app`, legacy cleanup, `.strings` plist validity, and Apple HIG icon geometry**

Replace `Tests/test_bundle.swift` with:

```swift
import Foundation
import AppKit

@main
struct BundleVerificationTest {
    static func main() throws {
        let fm = FileManager.default
        let legacyURL = URL(fileURLWithPath: "/Applications/Bug On Mac exe.app")
        assert(!fm.fileExists(atPath: legacyURL.path), "Legacy /Applications/Bug On Mac exe.app must be removed")

        let appURL = URL(fileURLWithPath: "/Applications/Bug On EXE.app")
        assert(fm.fileExists(atPath: appURL.path), "Installed app bundle must exist at /Applications/Bug On EXE.app")

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        assert(plist?["CFBundleIdentifier"] as? String == "com.stark.bugonmacexe")
        assert(plist?["CFBundleDisplayName"] as? String == "Bug On EXE")
        assert(plist?["CFBundleName"] as? String == "Bug On EXE")

        for lang in ["en", "vi"] {
            let stringsURL = appURL.appendingPathComponent("Contents/Resources/\(lang).lproj/Localizable.strings")
            assert(fm.fileExists(atPath: stringsURL.path), "\(lang).lproj/Localizable.strings must be bundled")
            let data = try Data(contentsOf: stringsURL)
            let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
            assert(dict?["window.title.manager"] == "Bug On EXE", "\(lang) strings must define Bug On EXE title")
        }

        let icnsURL = appURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let icnsAttr = try fm.attributesOfItem(atPath: icnsURL.path)
        let icnsSize = (icnsAttr[.size] as? NSNumber)?.intValue ?? 0
        assert(icnsSize > 10_000, "AppIcon.icns must be non-empty and multi-resolution (got \(icnsSize) bytes)")

        let previewURL = URL(fileURLWithPath: "Resources/AppIcon-Preview.png")
        assert(fm.fileExists(atPath: previewURL.path), "Resources/AppIcon-Preview.png must exist for README")
        let previewData = try Data(contentsOf: previewURL)
        guard let rep = NSBitmapImageRep(data: previewData) else {
            fatalError("Unable to decode Resources/AppIcon-Preview.png")
        }
        assert(rep.pixelsWide == 512 && rep.pixelsHigh == 512, "Preview icon must be 512x512")
        // Verify Apple HIG squircle outer margin: pixel (2, 2) must be completely transparent
        let cornerColor = rep.colorAt(x: 2, y: 2)
        assert((cornerColor?.alphaComponent ?? 1.0) < 0.01, "Outer corner of icon canvas must be transparent per Apple HIG squircle grid")
        // Center pixel must be opaque
        let centerColor = rep.colorAt(x: 256, y: 256)
        assert((centerColor?.alphaComponent ?? 0.0) > 0.95, "Center of icon must be opaque")

        let execURL = appURL.appendingPathComponent("Contents/MacOS/BugOnMacExe")
        assert(fm.isExecutableFile(atPath: execURL.path), "Main executable must exist and be executable")

        let projectorExecURL = appURL.appendingPathComponent("Contents/Resources/Flash Player.app/Contents/MacOS/Flash Player")
        assert(fm.isExecutableFile(atPath: projectorExecURL.path), "Bundled 64-bit Flash Player executable must exist")

        print("ALL BUNDLE VERIFICATION TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `test_bundle.swift` to verify it fails before running the updated build**

Run:
```bash
swiftc Tests/test_bundle.swift -o /tmp/test_bundle && /tmp/test_bundle
```
Expected: FAIL because `/Applications/Bug On Mac exe.app` still exists and `/Applications/Bug On EXE.app` does not.

- [ ] **Step 3: Update `scripts/build_app.sh` to build `Bug On EXE.app` and render the Apple HIG Liquid Glass "Bug ON" Switch icon (Mẫu B)**

In `scripts/build_app.sh`:
1. Set `APP_NAME="Bug On EXE.app"` and `LEGACY_INSTALL_PATH="/Applications/Bug On Mac exe.app"`. Remove `rm -rf "$LEGACY_INSTALL_PATH" "$DIST_DIR/Bug On Mac exe.app"`.
2. Replace the embedded `SWIFT_ICON` script so that for each `(px, name)` in `sizes` it draws **Mẫu B (Công Tắc "Bug ON" Kính Lỏng)** onto a transparent canvas:
   - **Apple HIG Squircle Grid (`824/1024 ≈ 0.8047`):** Inset the canvas by `0.0976 * px` (`cardRect`), corner radius `0.225 * cardRect.width`, using `NSBezierPath(roundedRect:xRadius:yRadius:)`.
   - **macOS Dock Drop Shadow:** Save graphics state, apply `NSShadow` (`shadowOffset = NSSize(width: 0, height: -s * 0.028)`, `shadowBlurRadius = s * 0.045`, `shadowColor = NSColor.black.withAlphaComponent(0.38)`), fill the squircle base with Midnight Slate gradient (`#0F172A` top to `#1E293B` bottom), restore state.
   - **Ambient Inner Glow & Specular Rim:** Draw a subtle radial emerald/cyan inner glow inside the clipped squircle and stroke the squircle border (`1.5 * scale` width) with a top-to-bottom white gradient (`0.38` alpha top → `0.08` alpha bottom).
   - **Layer 2 — Emerald Liquid Glass "ON" Switch Track:** Rounded capsule at `x: 0.19*s, y: 0.43*s, width: 0.62*s, height: 0.31*s`, radius `0.155*s`, filled with linear gradient (`#10B981` → `#059669`), top inner highlight stroke (`white 0.45`), and when `px > 32`, draw `"ON"` at `x: 0.25*s` in bold rounded system font (`size: 0.082*s`, white `0.92` alpha).
   - **Layer 3a — 3D Glass Knob with Ruby Bug:** Circle centered at `(0.645*s, 0.585*s)` with radius `0.128*s`, drop shadow (`blur 0.02*s`, `y: -0.01*s`), white-to-ice-blue gradient (`#FFFFFF` → `#E2E8F0`). Inside the knob, draw the stylized Ruby Glass Bug: dark slate head (`#0F172A`) with two antennae, ruby gradient shell (`#FF4D6D` → `#E11D48`), white center seam line, and specular wing highlight.
   - **Layer 3b — Frosted Liquid Glass `.EXE` Pill:** Rounded rect at `x: 0.24*s, y: 0.17*s, width: 0.52*s, height: 0.16*s`, radius `0.05*s`, filled with translucent white gradient (`0.22` → `0.09` alpha), specular border (`white 0.42` alpha), and bold `.EXE` text centered in `#38BDF8` (sky cyan) at font size `0.092*s`.
   - Also copy `icon_256x256@2x.png` (`512×512`) to `$PROJ_ROOT/Resources/AppIcon-Preview.png`.

- [ ] **Step 4: Run `scripts/build_app.sh` and `test_bundle.swift` to verify the build and icon pass**

Run:
```bash
bash scripts/build_app.sh && swiftc Tests/test_bundle.swift -o /tmp/test_bundle && /tmp/test_bundle
```
Expected: PASS (`==> Successfully built and installed: /Applications/Bug On EXE.app` and `ALL BUNDLE VERIFICATION TESTS PASSED`).

- [ ] **Step 5: Commit**

```bash
git add scripts/build_app.sh Resources/AppIcon-Preview.png Tests/test_bundle.swift
git commit -m "feat(icon): render Apple HIG Liquid Glass Bug ON switch icon and build Bug On EXE.app"
```

---

### Task 3: Dual Release Packaging (`.dmg` & `.zip`), Bilingual `README.md` & GitHub Actions Release Workflow

**Files:**
- Create: `scripts/package_release.sh`
- Create: `README.md`
- Create: `.github/workflows/release.yml`
- Create: `Tests/test_release_package.swift`

**Interfaces:**
- Consumes: `scripts/build_app.sh`, `dist/Bug On EXE.app`, `Resources/AppIcon-Preview.png` from Task 2
- Produces:
  - `dist/Bug-On-EXE-macOS.zip`
  - `dist/Bug-On-EXE-macOS.dmg`
  - `README.md`
  - `.github/workflows/release.yml`

- [ ] **Step 1: Write the failing test `Tests/test_release_package.swift`**

Create `Tests/test_release_package.swift`:

```swift
import Foundation

@main
struct ReleasePackageTest {
    static func main() throws {
        let fm = FileManager.default
        let zipURL = URL(fileURLWithPath: "dist/Bug-On-EXE-macOS.zip")
        let dmgURL = URL(fileURLWithPath: "dist/Bug-On-EXE-macOS.dmg")
        let readmeURL = URL(fileURLWithPath: "README.md")
        let workflowURL = URL(fileURLWithPath: ".github/workflows/release.yml")

        assert(fm.fileExists(atPath: zipURL.path), "Release ZIP must exist at dist/Bug-On-EXE-macOS.zip")
        assert(fm.fileExists(atPath: dmgURL.path), "Release DMG must exist at dist/Bug-On-EXE-macOS.dmg")
        assert(fm.fileExists(atPath: readmeURL.path), "README.md must exist")
        assert(fm.fileExists(atPath: workflowURL.path), ".github/workflows/release.yml must exist")

        let readme = try String(contentsOf: readmeURL, encoding: .utf8)
        assert(readme.contains("Bug On EXE"), "README.md must document Bug On EXE")
        assert(readme.contains("Resources/AppIcon-Preview.png"), "README.md must embed AppIcon-Preview.png")
        assert(readme.contains("xattr -cr"), "README.md must include Gatekeeper quarantine removal tip")

        // Verify extracting the ZIP with ditto preserves executable bit and code signature
        let extractDir = fm.temporaryDirectory.appendingPathComponent("BugOnExeZipVerify-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: extractDir) }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        assert(unzip.terminationStatus == 0, "ditto -x -k must succeed")

        let extractedApp = extractDir.appendingPathComponent("Bug On EXE.app")
        let extractedExec = extractedApp.appendingPathComponent("Contents/MacOS/BugOnMacExe")
        let extractedFlash = extractedApp.appendingPathComponent("Contents/Resources/Flash Player.app/Contents/MacOS/Flash Player")
        assert(fm.isExecutableFile(atPath: extractedExec.path), "Extracted main binary must be executable")
        assert(fm.isExecutableFile(atPath: extractedFlash.path), "Extracted Flash Player binary must be executable")

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--deep", "--strict", extractedApp.path]
        try codesign.run()
        codesign.waitUntilExit()
        assert(codesign.terminationStatus == 0, "Extracted Bug On EXE.app must pass codesign --verify --deep --strict")

        print("ALL RELEASE PACKAGE TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `test_release_package.swift` to verify it fails**

Run:
```bash
swiftc Tests/test_release_package.swift -o /tmp/test_release_package && /tmp/test_release_package
```
Expected: FAIL with `Release ZIP must exist at dist/Bug-On-EXE-macOS.zip`.

- [ ] **Step 3: Implement `scripts/package_release.sh`, `README.md`, and `.github/workflows/release.yml`**

1. Create `scripts/package_release.sh` (`chmod +x`):
   - Runs `bash "$SCRIPT_DIR/build_app.sh"`.
   - Packages `$DIST_DIR/Bug On EXE.app` into `$DIST_DIR/Bug-On-EXE-macOS.zip` using `ditto -c -k --sequesterRsrc --keepParent "$DIST_DIR/Bug On EXE.app" "$DIST_DIR/Bug-On-EXE-macOS.zip"`.
   - Stages a temporary directory containing `Bug On EXE.app` and `ln -s /Applications "$STAGE_DIR/Applications"`, then builds `$DIST_DIR/Bug-On-EXE-macOS.dmg` via `hdiutil create -volname "Bug On EXE" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DIST_DIR/Bug-On-EXE-macOS.dmg"`.
2. Create `README.md` (bilingual Vietnamese & English) featuring `Resources/AppIcon-Preview.png`, brand explanation (*"Bug On" = "Bất Ổn"*), key features (instant `.exe` / `.swf` Flash Projector extraction, 1-click Default App registration, macOS 26 Liquid Glass launcher, automatic `FlashPlayerTrust`), download instructions for `Bug-On-EXE-macOS.dmg` / `Bug-On-EXE-macOS.zip`, first-launch Gatekeeper note (`xattr -cr "/Applications/Bug On EXE.app"`), and build-from-source commands.
3. Create `.github/workflows/release.yml` triggered on `push: tags: ['v*']` and `workflow_dispatch` on `macos-latest` that runs `bash scripts/package_release.sh` and uploads `dist/Bug-On-EXE-macOS.dmg` and `dist/Bug-On-EXE-macOS.zip` to the GitHub Release via `softprops/action-gh-release@v2`.

- [ ] **Step 4: Run `scripts/package_release.sh` and all 9 test suites to verify everything passes**

Run:
```bash
bash scripts/package_release.sh && \
swiftc Tests/test_release_package.swift -o /tmp/test_release_package && /tmp/test_release_package && \
swiftc Tests/test_bundle.swift -o /tmp/test_bundle && /tmp/test_bundle
```
Expected: PASS (`ALL RELEASE PACKAGE TESTS PASSED` and `ALL BUNDLE VERIFICATION TESTS PASSED`).

- [ ] **Step 5: Commit**

```bash
git add scripts/package_release.sh README.md .github/workflows/release.yml Tests/test_release_package.swift
git commit -m "feat(release): add DMG/ZIP release packager, bilingual README, and GitHub Release workflow"
```
