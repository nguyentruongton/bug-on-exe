# Bug On Mac exe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and install `/Applications/Bug On Mac exe.app` for macOS 26.7.2 (`x86_64` Intel i5) so the user can set it as the default app for `.exe` files and double-click Adobe Flash `.exe` projectors (such as IC3 GS6 tests) to run them natively.

**Architecture:** A native Swift (AppKit) macOS application (`com.stark.bugonmacexe`) that registers as a handler for `.exe` and `.swf` files in Finder. On file open, `ExeSwfExtractor` extracts the embedded `.swf` payload (via the `0xFA123456` Flash Projector footer or fallback SWF signature scan), `SessionManager` stages the `.swf` with sibling symlinks and configures `FlashPlayerTrust`, and `ProjectorRunner` launches the bundled 64-bit macOS `Flash Player.app` projector. When launched directly without a file, `LauncherWindowController` displays a management window to set the default `.exe` handler, browse `/Users/stark/Documents/IC3`, or drag-and-drop `.exe` files.

**Tech Stack:** Swift 5/6 (`/usr/bin/swiftc`), AppKit, CoreServices (LaunchServices), Compression (`zlib`), bundled Adobe Flash Player Projector 32.0.0.465 (`x86_64` macOS).

**Spec:** [2026-10-28-flash-exe-runner-design.md](file:///Users/stark/Library/Application%20Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/brain/88052047-fbf4-4549-8287-d1ad8ab248f3/2026-10-28-flash-exe-runner-design.md)

## Global Constraints

- **Target OS & Arch:** macOS 26.7.2 (`x86_64` Intel Core i5), compiled with `/usr/bin/swiftc -target x86_64-apple-macosx13.0` (compatible with macOS 13 through 26).
- **App Name & Paths:** Display name `Bug On Mac exe`, Bundle ID `com.stark.bugonmacexe`, project root `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe`, installed app path `/Applications/Bug On Mac exe.app`.
- **Gatekeeper & Signing:** Both `/Applications/Bug On Mac exe.app` and `Contents/Resources/Flash Player.app` must have quarantine attributes removed (`xattr -cr`) and ad-hoc signatures applied (`codesign --force --deep --sign -`).
- **UI Copy Language:** Vietnamese for all user-facing labels, buttons, and error alerts.

## Review Focus

- **Truncated `.exe` (< 8 bytes) or footer `swfLength` larger than file size:** Must return `ExtractorError.notAFlashExecutable` without crashing on an out-of-bounds `Data` range slice (tested in Task 1).
- **`.exe` with trailing bytes (e.g. Authenticode signature) after the `0xFA123456` footer:** Fallback scanner must locate the embedded `CWS`/`FWS` header and extract the valid SWF payload (tested in Task 1).
- **Non-Flash `.exe` containing a random `"CWS"` ASCII byte sequence in code:** Fallback scanner must validate SWF version (`1...45`) and `zlib` decompression stream before accepting, rejecting false positives with `ExtractorError.notAFlashExecutable` (tested in Task 1).
- **Paths with spaces and parentheses (e.g. `/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe`):** `SessionManager` and `FlashPlayerTrust` must handle spaces and parentheses accurately without escaping bugs (tested in Task 2).
- **Opening the same `.exe` file repeatedly:** `SessionManager.prepareSession(for:swfData:)` must overwrite existing extracted `.swf` and ignore already-existing sibling symlinks without throwing a file-exists error (tested in Task 2).

---

### Task 1: SWF Payload Extractor (`ExeSwfExtractor`)

**Files:**
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/Core/ExeSwfExtractor.swift`
- Test: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Tests/test_extractor.swift`

**Interfaces:**
- Consumes: `Foundation`, `Compression`
- Produces:
  ```swift
  public enum ExtractorError: Error, Equatable {
      case fileUnreadable(String)
      case notAFlashExecutable
  }

  public struct SwfPayload: Equatable {
      public let data: Data
      public let signature: String // "FWS", "CWS", or "ZWS"
      public let version: UInt8
      public let uncompressedLength: UInt32
  }

  public enum ExeSwfExtractor {
      public static func extract(from fileURL: URL) throws -> SwfPayload
      public static func extract(from data: Data) throws -> SwfPayload
  }
  ```

- [ ] **Step 1: Initialize git repo and write the failing extractor tests in `Tests/test_extractor.swift`**

```swift
import Foundation

func assertThrowsNotFlash(_ data: Data, _ message: String) {
    do {
        _ = try ExeSwfExtractor.extract(from: data)
        fatalError("Expected notAFlashExecutable for \(message)")
    } catch ExtractorError.notAFlashExecutable {
        // Expected
    } catch {
        fatalError("Unexpected error \(error) for \(message)")
    }
}

@main
struct ExtractorTestRunner {
    static func main() throws {
        // 1. Truncated / tiny data (< 8 bytes)
        assertThrowsNotFlash(Data([0x4D, 0x5A, 0x90]), "tiny 3-byte file")

        // 2. Corrupt footer with swfLength > fileSize
        var badFooter = Data(repeating: 0x00, count: 32)
        badFooter.append(contentsOf: [0x56, 0x34, 0x12, 0xFA, 0xFF, 0xFF, 0x00, 0x00])
        assertThrowsNotFlash(badFooter, "swfLength larger than file")

        // 3. False positive "CWS" in a normal binary without valid zlib payload
        var fakeExe = Data([0x4D, 0x5A, 0x90, 0x00])
        fakeExe.append(contentsOf: Array("CWS\u{09}xxxxNOT_ZLIB_DATA".utf8))
        assertThrowsNotFlash(fakeExe, "false positive CWS")

        // 4. Trailing bytes after 0xFA123456 footer (fallback scan on valid FWS)
        var fws = Data([0x46, 0x57, 0x53, 0x09]) // FWS v9
        let fwsLen: UInt32 = 20
        withUnsafeBytes(of: fwsLen.littleEndian) { fws.append(contentsOf: $0) }
        fws.append(Data(repeating: 0x00, count: 12)) // rect + frame rate + frame count + end tag
        var exeWithOverlay = Data([0x4D, 0x5A, 0x90, 0x00, 0x00, 0x00])
        exeWithOverlay.append(fws)
        exeWithOverlay.append(contentsOf: [0x56, 0x34, 0x12, 0xFA])
        withUnsafeBytes(of: fwsLen.littleEndian) { exeWithOverlay.append(contentsOf: $0) }
        exeWithOverlay.append(Data(repeating: 0xAB, count: 64)) // trailing overlay
        let overlayPayload = try ExeSwfExtractor.extract(from: exeWithOverlay)
        assert(overlayPayload.signature == "FWS" && overlayPayload.version == 9 && overlayPayload.data.count == 20)

        // 5. Real IC3 GS6 Flash Projector .exe file
        let realURL = URL(fileURLWithPath: "/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe")
        let realPayload = try ExeSwfExtractor.extract(from: realURL)
        assert(realPayload.signature == "CWS")
        assert(realPayload.version == 9)
        assert(realPayload.data.count == 1_208_512)
        assert(realPayload.uncompressedLength == 850_135)
        print("ALL EXTRACTOR TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `swiftc` to verify the test fails because `ExeSwfExtractor` is not defined**

Run: `swiftc -parse-as-library Sources/Core/ExeSwfExtractor.swift Tests/test_extractor.swift -o /tmp/test_extractor && /tmp/test_extractor`
Expected: FAIL (`no such file or directory: 'Sources/Core/ExeSwfExtractor.swift'`)

- [ ] **Step 3: Implement `ExeSwfExtractor` in `Sources/Core/ExeSwfExtractor.swift`**

Implement:
- Direct `.swf` check at byte 0 (`validateSwfCandidate(_:)`).
- Fast-path check at `data.count - 8`: read little-endian `UInt32` magic (`0xFA123456`) and `swfLength`, verify `swfLength >= 12 && swfLength <= data.count - 8`, and pass slice to `validateSwfCandidate(_:)`.
- Fallback scan: search for `[0x46, 0x57, 0x53]` (`FWS`) or `[0x43, 0x57, 0x53]` (`CWS`) after byte 0 where `version` is in `1...45` and `uncompressedLength` is in `12...100_000_000`. For `FWS`, slice is `uncompressedLength` bytes; for `CWS`, verify `zlib` header byte (`(b0 & 0x0F) == 8`) and locate the exact compressed stream or trailing `0xFA123456` marker, decompressing via `compression_decode_buffer` (`COMPRESSION_ZLIB`) to confirm the decompressed size equals `uncompressedLength - 8`.

- [ ] **Step 4: Run test to verify all 5 extractor checks pass**

Run: `swiftc -parse-as-library Sources/Core/ExeSwfExtractor.swift Tests/test_extractor.swift -o /tmp/test_extractor && /tmp/test_extractor`
Expected: `ALL EXTRACTOR TESTS PASSED`

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/Core/ExeSwfExtractor.swift Tests/test_extractor.swift
git commit -m "feat: add ExeSwfExtractor with footer fast-path and fallback SWF validation"
```

---

### Task 2: Session Staging, Sibling Symlinks & `FlashPlayerTrust` (`SessionManager`)

**Files:**
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/Core/SessionManager.swift`
- Test: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Tests/test_session.swift`

**Interfaces:**
- Consumes: `SwfPayload` from `ExeSwfExtractor`
- Produces:
  ```swift
  public struct PreparedSession {
      public let sessionDirectory: URL
      public let swfFileURL: URL
      public let trustConfigURL: URL
  }

  public final class SessionManager {
      public let cacheRootURL: URL
      public let trustConfigURL: URL
      public init(cacheRootURL: URL? = nil, trustConfigURL: URL? = nil)
      public func prepareSession(for sourceExeURL: URL, payload: SwfPayload) throws -> PreparedSession
  }
  ```

- [ ] **Step 1: Write the failing session manager tests in `Tests/test_session.swift`**

```swift
import Foundation

@main
struct SessionTestRunner {
    static func main() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BugOnMacExeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let cacheRoot = tempRoot.appendingPathComponent("Caches")
        let trustFile = tempRoot.appendingPathComponent("FlashPlayerTrust/BugOnMacExe.cfg")
        let manager = SessionManager(cacheRootURL: cacheRoot, trustConfigURL: trustFile)

        let sourceURL = URL(fileURLWithPath: "/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe")
        let payload = try ExeSwfExtractor.extract(from: sourceURL)

        // 1. Prepare session for path with spaces & parentheses
        let session1 = try manager.prepareSession(for: sourceURL, payload: payload)
        assert(FileManager.default.fileExists(atPath: session1.swfFileURL.path))
        let trustContent = try String(contentsOf: trustFile, encoding: .utf8)
        assert(trustContent.contains(cacheRoot.path))
        assert(trustContent.contains(sourceURL.deletingLastPathComponent().path))

        // 2. Idempotency: preparing the exact same file a second time succeeds without error
        let session2 = try manager.prepareSession(for: sourceURL, payload: payload)
        assert(session1.swfFileURL == session2.swfFileURL)
        print("ALL SESSION TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `swiftc` to verify the test fails**

Run: `swiftc -parse-as-library Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Tests/test_session.swift -o /tmp/test_session && /tmp/test_session`
Expected: FAIL (`no such file or directory: 'Sources/Core/SessionManager.swift'`)

- [ ] **Step 3: Implement `SessionManager` in `Sources/Core/SessionManager.swift`**

Implement:
- Default `cacheRootURL`: `~/Library/Caches/BugOnMacExe/Sessions`.
- Default `trustConfigURL`: `~/Library/Preferences/Macromedia/Flash Player/#Security/FlashPlayerTrust/BugOnMacExe.cfg`.
- `prepareSession(for:payload:)`:
  - Creates a deterministic folder name `<8-char-hash>-<base-name>` inside `cacheRootURL`.
  - Writes `payload.data` atomically to `<base-name>.swf` inside that folder.
  - Iterates non-`.exe` items in `sourceExeURL.deletingLastPathComponent()` and creates symlinks in the session directory (skipping if the symlink already exists).
  - Ensures `trustConfigURL` parent directories exist and appends `cacheRootURL.path` and `sourceExeURL.deletingLastPathComponent().path` if not already present.

- [ ] **Step 4: Run test to verify it passes**

Run: `swiftc -parse-as-library Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Tests/test_session.swift -o /tmp/test_session && /tmp/test_session`
Expected: `ALL SESSION TESTS PASSED`

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/Core/SessionManager.swift Tests/test_session.swift
git commit -m "feat: add SessionManager for SWF staging, sibling symlinks, and FlashPlayerTrust"
```

---

### Task 3: Default `.exe` Handler & IC3 File Discovery (`DefaultAppManager`)

**Files:**
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/Core/DefaultAppManager.swift`
- Test: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Tests/test_default_app.swift`

**Interfaces:**
- Consumes: `Foundation`, `CoreServices`, `AppKit`
- Produces:
  ```swift
  public enum DefaultAppManager {
      public static let bundleIdentifier = "com.stark.bugonmacexe"
      public static let exeUTIs: [String]
      public static func isDefaultHandlerForExe() -> Bool
      @discardableResult
      public static func setAsDefaultHandlerForExe() -> Bool
      public static func discoverExeFiles(in rootDirectory: URL) -> [URL]
  }
  ```

- [ ] **Step 1: Write the failing test in `Tests/test_default_app.swift`**

```swift
import Foundation

@main
struct DefaultAppTestRunner {
    static func main() throws {
        let ic3Root = URL(fileURLWithPath: "/Users/stark/Documents/IC3")
        let discovered = DefaultAppManager.discoverExeFiles(in: ic3Root)
        assert(discovered.count >= 4, "Should discover at least the 4 GS6 Level 3 .exe files")
        assert(discovered.first?.pathExtension.lowercased() == "exe")
        _ = DefaultAppManager.isDefaultHandlerForExe()
        print("ALL DEFAULT APP TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `swiftc` to verify the test fails**

Run: `swiftc -parse-as-library Sources/Core/DefaultAppManager.swift Tests/test_default_app.swift -o /tmp/test_default_app && /tmp/test_default_app`
Expected: FAIL (`no such file or directory: 'Sources/Core/DefaultAppManager.swift'`)

- [ ] **Step 3: Implement `DefaultAppManager` in `Sources/Core/DefaultAppManager.swift`**

Implement:
- `exeUTIs = ["com.microsoft.windows-executable", "public.executable", "com.stark.bugonmacexe.exe"]` plus dynamic UTIs derived via `UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, "exe" as CFString, nil)`.
- `isDefaultHandlerForExe()` using `LSCopyDefaultRoleHandlerForContentType` case-insensitive comparison against `bundleIdentifier`.
- `setAsDefaultHandlerForExe()` calling `LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleIdentifier as CFString)` across all `exeUTIs` and `com.macromedia.shockwave-flash`.
- `discoverExeFiles(in:)` recursively enumerating `.exe` files sorted alphabetically by filename.

- [ ] **Step 4: Run test to verify it passes**

Run: `swiftc -parse-as-library Sources/Core/DefaultAppManager.swift Tests/test_default_app.swift -o /tmp/test_default_app && /tmp/test_default_app`
Expected: `ALL DEFAULT APP TESTS PASSED`

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/Core/DefaultAppManager.swift Tests/test_default_app.swift
git commit -m "feat: add DefaultAppManager for LaunchServices .exe registration and IC3 discovery"
```

---

### Task 4: Native macOS GUI (`ProjectorRunner`, `LauncherWindowController`, `AppDelegate`, `main.swift`)

**Files:**
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/App/ProjectorRunner.swift`
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/App/LauncherWindowController.swift`
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/App/AppDelegate.swift`
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Sources/App/main.swift`

**Interfaces:**
- Consumes: `ExeSwfExtractor`, `SessionManager`, `DefaultAppManager`
- Produces: Executable binary `BugOnMacExe` inside `Bug On Mac exe.app/Contents/MacOS/BugOnMacExe`

- [ ] **Step 1: Implement `ProjectorRunner.swift`**

Implement:
- `public final class ProjectorRunner` with `public static func run(fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void)`:
  - Calls `ExeSwfExtractor.extract(from: fileURL)` and `SessionManager().prepareSession(for: fileURL, payload: payload)`.
  - Locates `Flash Player.app` inside `Bundle.main.resourceURL?.appendingPathComponent("Flash Player.app")` (with fallback to `/Applications/Flash Player.app`).
  - Launches `session.swfFileURL` using `NSWorkspace.shared.open([session.swfFileURL], withApplicationAt: projectorURL, configuration: config, completionHandler: ...)`.
  - Records `fileURL.path` in `UserDefaults.standard` key `"RecentExeFiles"` (up to 20 entries).

- [ ] **Step 2: Implement `LauncherWindowController.swift`, `AppDelegate.swift`, and `main.swift`**

Implement:
- `LauncherWindowController`:
  - Window titled `"Bug On Mac exe — Trình chạy Flash .exe"`, size `640x480`.
  - Top banner showing current default `.exe` handler status and button `"Đặt làm ứng dụng mặc định mở file .exe"`.
  - Table/list of discovered `.exe` files in `/Users/stark/Documents/IC3` and recent files, where double-clicking a row or clicking `"Chạy bài đã chọn"` invokes `ProjectorRunner.run(fileURL:)`.
  - Button `"Mở file .exe khác..."` (`NSOpenPanel` filtering `.exe` and `.swf`) and drag-and-drop support (`NSFilenamesPboardType` / `.fileURL`) on the window content view.
- `AppDelegate`:
  - Tracks `didOpenFileFromFinder: Bool`.
  - Implements `application(_:openFiles:)` and `application(_:open:)`: sets `didOpenFileFromFinder = true`, runs each file via `ProjectorRunner.run(fileURL:)`, shows a Vietnamese `NSAlert` (`"File .exe này không phải là ứng dụng Adobe Flash Projector..."`) if extraction fails, and terminates the helper wrapper (`NSApp.terminate(nil)`) 1.5s after successfully handing off to `Flash Player.app` when launched solely via Finder double-click so no extra Dock icon/window lingers.
  - In `applicationDidFinishLaunching(_:)`: waits 0.15s; if `didOpenFileFromFinder == false` (or CLI `--self-test` flag is passed), shows `LauncherWindowController`. Supports `--extract-test <exe-path>` CLI flag for automated end-to-end verification.

- [ ] **Step 3: Compile all Swift sources to verify clean build**

Run:
```bash
swiftc \
  Sources/Core/ExeSwfExtractor.swift \
  Sources/Core/SessionManager.swift \
  Sources/Core/DefaultAppManager.swift \
  Sources/App/ProjectorRunner.swift \
  Sources/App/LauncherWindowController.swift \
  Sources/App/AppDelegate.swift \
  Sources/App/main.swift \
  -o /tmp/BugOnMacExe
```
Expected: Exits with code `0` and produces `/tmp/BugOnMacExe` binary.

- [ ] **Step 4: Commit Task 4**

```bash
git add Sources/App/
git commit -m "feat: add AppKit GUI, Finder openFiles delegate, and ProjectorRunner"
```

---

### Task 5: App Bundle Packaging, Bundled 64-bit `Flash Player.app`, and Installation

**Files:**
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/Resources/Info.plist`
- Create: `/Users/stark/Library/Application Support/AgentProfiles/antigravity/desktop/pixel11series/home/.gemini/antigravity/scratch/bug-on-mac-exe/scripts/build_app.sh`

**Interfaces:**
- Consumes: All `Sources/**/*.swift`
- Produces: `/Applications/Bug On Mac exe.app`

- [ ] **Step 1: Create `Resources/Info.plist` with `.exe` and `.swf` document type registrations**

Include:
- `CFBundleName` = `Bug On Mac exe`, `CFBundleDisplayName` = `Bug On Mac exe`, `CFBundleExecutable` = `BugOnMacExe`, `CFBundleIdentifier` = `com.stark.bugonmacexe`.
- `CFBundleDocumentTypes` registering role `Viewer` / `Shell` for extensions `exe`, `EXE`, `swf`, `SWF` and content types `com.microsoft.windows-executable`, `public.executable`, `com.macromedia.shockwave-flash`.

- [ ] **Step 2: Create `scripts/build_app.sh` to bundle `Flash Player.app`, generate `AppIcon.icns`, compile, sign, and install `/Applications/Bug On Mac exe.app`**

Implement in `scripts/build_app.sh`:
1. Download and mount the archived official macOS 64-bit Adobe Flash Player 32.0.0.465 Projector DMG (`flashplayer_32_sa.dmg` from `archive.org`), copy `Flash Player.app` into `Vendor/Flash Player.app`, and verify with `file "Vendor/Flash Player.app/Contents/MacOS/Flash Player"` that it is `Mach-O 64-bit executable x86_64`.
2. Generate `AppIcon.icns` via Swift/CoreGraphics + `iconutil`.
3. Assemble `dist/Bug On Mac exe.app`, copy `Info.plist`, `AppIcon.icns`, and `Vendor/Flash Player.app` into `Contents/Resources/`, and compile `Contents/MacOS/BugOnMacExe`.
4. Strip quarantine attributes (`xattr -cr "dist/Bug On Mac exe.app"`), ad-hoc sign both the inner `Flash Player.app` and outer `Bug On Mac exe.app` (`codesign --force --deep --sign -`), copy to `/Applications/Bug On Mac exe.app`, and register with LaunchServices (`lsregister -f "/Applications/Bug On Mac exe.app"`).

- [ ] **Step 3: Run `scripts/build_app.sh` and verify the installed `.app` bundle**

Run:
```bash
bash scripts/build_app.sh && \
codesign -vvv "/Applications/Bug On Mac exe.app" && \
"/Applications/Bug On Mac exe.app/Contents/MacOS/BugOnMacExe" --extract-test "/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe"
```
Expected:
- `/Applications/Bug On Mac exe.app: valid on disk`
- `EXTRACT_TEST_OK: CWS v9 (1208512 bytes)`

- [ ] **Step 4: Commit Task 5**

```bash
git add Resources/Info.plist scripts/build_app.sh .gitignore
git commit -m "build: package Bug On Mac exe.app with bundled 64-bit Flash Player projector"
```
