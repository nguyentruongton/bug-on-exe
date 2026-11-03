# Portable EXE (7-Zip SFX & Win32) & On-Demand Wine Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade **Bug On EXE** into a dual-engine `.exe` launcher that preserves instant native macOS Flash execution while supporting portable 7-Zip SFX (`.sevenZipSfx`) and standalone Windows (`.standaloneWin32`) `.exe` files via persistent macOS extraction and an in-app on-demand Wine runtime installer with a real-time progress window.

**Architecture:** Add `PortableExeExtractor` and `PortableAppSessionManager` (`Sources/Core/PortableExeExtractor.swift`) to classify `.exe` files into `.flash`, `.sevenZipSfx`, or `.standaloneWin32`, and unpack 7z SFX archives once via `/usr/bin/tar` into `~/Library/Application Support/BugOnExe/PortableApps/<hash>-<name>/` (removing `KillDuplicate.cmd` and resolving `RunProgram`). Add `WineRuntimeManager` (`Sources/Core/WineRuntimeManager.swift`) and `WineInstallProgressWindowController` (`Sources/App/WineInstallProgressWindowController.swift`) to detect existing Wine installations, prompt and download standalone macOS Wine (`wine-devel-11.21-osx64.tar.xz` from `Gcenx/macOS_Wine_builds`) into `~/Library/Application Support/BugOnExe/Runtime/` with live progress, and execute Windows binaries in their own working directory. Route non-Flash `.exe` files in `ProjectorRunner` and `AppDelegate` through this pipeline.

**Tech Stack:** Swift 6.3 (`swiftc`), AppKit, `URLSession`, `/usr/bin/tar` (`libarchive`), `/usr/bin/xattr`.

**Spec:** `docs/superpowers/specs/2026-11-03-portable-exe-wine-runtime-design.md`

## Global Constraints

- Keep initial `Bug On EXE.app` bundle lightweight (~18MB) without bundling Wine inside `Contents/Resources/`.
- Always attempt `ExeSwfExtractor.extract` first so Flash `.exe` and `.swf` files continue launching via native `Flash Player.app` with zero regression.
- Extract 7-Zip SFX portable archives into `~/Library/Application Support/BugOnExe/PortableApps/<fnv1aHash>-<baseName>/` (using `SessionManager.realUserHomeDirectory()`), delete `KillDuplicate.cmd` if present, and cache via `.extracted_ok` so save files persist and subsequent launches skip extraction.
- Never require Homebrew or `sudo` password; install standalone Wine into `~/Library/Application Support/BugOnExe/Runtime/` and strip quarantine via `/usr/bin/xattr -cr`.
- Maintain complete bilingual (`EN` / `VI`) localization across `LocalizationManager.swift`, `Resources/en.lproj/Localizable.strings`, and `Resources/vi.lproj/Localizable.strings`.

## Review Focus

1. **Escaped quotes and `%%T\\` prefix in 7z SFX `RunProgram`:** Real `7z SFX Constructor` headers (like `Plants_Vs_Zombies.exe`) write `RunProgram="\"Plants Vs Zombies VN Portable.exe\""` or `RunProgram="\"%%T\\sub\\game.exe\""` with CRLF line endings; failing to unescape `\"` or strip `%%T\\` breaks inner `.exe` resolution — pinned in Task 1 (`Tests/test_portable_extractor.swift`).
2. **Leftover `KillDuplicate.cmd` or re-extraction wiping user saves:** Extracting a 7z SFX archive without deleting `KillDuplicate.cmd` or overwriting an already-extracted folder on second launch loses user save data — pinned in Task 1 (`Tests/test_portable_extractor.swift` cache reuse and `KillDuplicate.cmd` removal test).
3. **False positive 7z signature at offset 0 or non-MZ files:** Raw `.7z` archives (offset 0) or corrupted non-PE files must not be misclassified as `.sevenZipSfx` or `.standaloneWin32` executables — pinned in Task 1 (`Tests/test_portable_extractor.swift`).
4. **Missing working directory when launching portable Win32 games:** Launching `Plants Vs Zombies VN Portable.exe` via Wine with default working directory `/` causes immediate crash (`main.pak` / `bass.dll` not found) — pinned in Task 2 (`Tests/test_wine_runtime.swift` verifying `currentDirectoryURL` and `WINEPREFIX`).
5. **Valid `.strings` plist formatting for new Wine UI copy:** Any unescaped quotes or missing semicolons in `Resources/*.lproj/Localizable.strings` breaks bundle localization — pinned in Task 2 (`Tests/test_localization.swift`) and Task 3 (`Tests/test_bundle.swift`).

---

### Task 1: Executable Classifier (`ExeExecutableKind`) & Persistent 7-Zip SFX Unpacker (`PortableExeExtractor.swift`)

**Files:**
- Modify: `Sources/Core/SessionManager.swift:4-8` (add `Equatable` conformance to `PreparedSession`)
- Create: `Sources/Core/PortableExeExtractor.swift`
- Create: `Tests/test_portable_extractor.swift`

**Interfaces:**
- Consumes:
  - `ExeSwfExtractor.extract(from: Data) throws -> SwfPayload` (`Sources/Core/ExeSwfExtractor.swift`)
  - `SessionManager.realUserHomeDirectory() -> URL` (`Sources/Core/SessionManager.swift`)
- Produces:
  - `public struct PreparedSession: Equatable` (`Sources/Core/SessionManager.swift`)
  - `public enum PortableExtractorError: Error, Equatable` (`.fileUnreadable(String)`, `.notAValidExecutable`, `.archiveExtractionFailed(String)`, `.innerExecutableNotFound`)
  - `public enum ExeExecutableKind: Equatable`:
    - `.flash(SwfPayload)`
    - `.sevenZipSfx(archiveOffset: Int, runProgram: String?)`
    - `.standaloneWin32`
  - `public enum PortableExeExtractor`:
    - `public static func classify(fileURL: URL) throws -> ExeExecutableKind`
    - `public static func classify(data: Data) throws -> ExeExecutableKind`
    - `public static func parseSfxRunProgram(from configData: Data) -> String?`
  - `public final class PortableAppSessionManager`:
    - `public let portableRootURL: URL`
    - `public init(portableRootURL: URL? = nil)`
    - `public func preparePortableSession(for sourceExeURL: URL, archiveOffset: Int, runProgram: String?) throws -> URL`

- [ ] **Step 1: Write the failing test `Tests/test_portable_extractor.swift`**

Create `Tests/test_portable_extractor.swift`:

```swift
import Foundation

@main
struct PortableExtractorTestRunner {
    static func main() throws {
        // 1. Flash executable is classified as .flash
        var fws = Data([0x46, 0x57, 0x53, 0x09])
        let fwsLen: UInt32 = 20
        withUnsafeBytes(of: fwsLen.littleEndian) { fws.append(contentsOf: $0) }
        fws.append(Data(repeating: 0x00, count: 12))
        let flashKind = try PortableExeExtractor.classify(data: fws)
        guard case .flash(let payload) = flashKind, payload.signature == "FWS" else {
            fatalError("Expected .flash for valid FWS payload")
        }

        // 2. Non-MZ, non-SWF data throws .notAValidExecutable (including raw 7z at offset 0)
        let raw7zAtZero = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00])
        do {
            _ = try PortableExeExtractor.classify(data: raw7zAtZero)
            fatalError("Expected notAValidExecutable for raw 7z at offset 0")
        } catch PortableExtractorError.notAValidExecutable {
            // Expected
        }

        // 3. Standalone Win32 PE32 (MZ header without Flash or 7z signature) -> .standaloneWin32
        var standalonePe = Data([0x4D, 0x5A, 0x90, 0x00])
        standalonePe.append(Data(repeating: 0x20, count: 128))
        let win32Kind = try PortableExeExtractor.classify(data: standalonePe)
        assert(win32Kind == .standaloneWin32, "Expected .standaloneWin32 for plain MZ binary")

        // 4. 7z SFX header parsing handles escaped quotes, %%T\\ prefix, and CRLF
        let sfxConfig = """
        ;!@Install@!UTF-8!\r
        GUIMode="1"\r
        InstallPath="%Temp%\\\\data"\r
        PreExtract="%%P:hidcon:cmd /c \\"\\"%%T\\\\KillDuplicate.cmd\\" \\"%%T\\" \\"%%M\\"\\""\r
        RunProgram="\\"Plants Vs Zombies VN Portable.exe\\""\r
        Delete="%%T"\r
        ;!@InstallEnd@!
        """.data(using: .utf8)!
        assert(PortableExeExtractor.parseSfxRunProgram(from: sfxConfig) == "Plants Vs Zombies VN Portable.exe")

        let sfxConfigWithTempPrefix = """
        ;!@Install@!UTF-8!\r
        RunProgram="\\"%%T\\\\bin\\\\Zuma.exe\\" -fullscreen"\r
        ;!@InstallEnd@!
        """.data(using: .utf8)!
        assert(PortableExeExtractor.parseSfxRunProgram(from: sfxConfigWithTempPrefix) == "bin/Zuma.exe")

        // 5. 7z SFX classification + persistent extraction + KillDuplicate.cmd removal + save preservation
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("BugOnExePortableTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }
        let buildDir = tempRoot.appendingPathComponent("src", isDirectory: true)
        try fm.createDirectory(at: buildDir, withIntermediateDirectories: true)

        let innerExeURL = buildDir.appendingPathComponent("Plants Vs Zombies VN Portable.exe")
        try Data([0x4D, 0x5A, 0x90, 0x00, 0x01, 0x02]).write(to: innerExeURL)
        let pakURL = buildDir.appendingPathComponent("main.pak")
        try Data("PAK_CONTENT".utf8).write(to: pakURL)
        let killCmdURL = buildDir.appendingPathComponent("KillDuplicate.cmd")
        try Data("@echo off\r\ntaskkill /f /im game.exe".utf8).write(to: killCmdURL)

        // Create a real archive payload supported by /usr/bin/tar and prefix it with MZ + SFX config + 7z magic
        // Note: /usr/bin/tar auto-detects archive format; for synthetic test without 7z CLI, test tar payload prefixed at archiveOffset
        let rawTarURL = tempRoot.appendingPathComponent("payload.tar")
        let tarProc = Process()
        tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProc.currentDirectoryURL = buildDir
        tarProc.arguments = ["-cf", rawTarURL.path, "Plants Vs Zombies VN Portable.exe", "main.pak", "KillDuplicate.cmd"]
        try tarProc.run()
        tarProc.waitUntilExit()
        assert(tarProc.terminationStatus == 0)

        var fakeSfxData = Data([0x4D, 0x5A, 0x90, 0x00])
        fakeSfxData.append(sfxConfig)
        let expectedOffset = fakeSfxData.count
        fakeSfxData.append(contentsOf: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
        let classifiedSfx = try PortableExeExtractor.classify(data: fakeSfxData)
        assert(classifiedSfx == .sevenZipSfx(archiveOffset: expectedOffset, runProgram: "Plants Vs Zombies VN Portable.exe"))

        // Build extractable SFX file using real tar payload at offset for PortableAppSessionManager test
        var extractableSfx = Data([0x4D, 0x5A, 0x90, 0x00])
        extractableSfx.append(sfxConfig)
        let tarOffset = extractableSfx.count
        extractableSfx.append(try Data(contentsOf: rawTarURL))
        let outerExeURL = tempRoot.appendingPathComponent("Plants_Vs_Zombies.exe")
        try extractableSfx.write(to: outerExeURL)

        let portableStoreRoot = tempRoot.appendingPathComponent("PortableApps", isDirectory: true)
        let sessionMgr = PortableAppSessionManager(portableRootURL: portableStoreRoot)
        let resolvedExe = try sessionMgr.preparePortableSession(
            for: outerExeURL,
            archiveOffset: tarOffset,
            runProgram: "Plants Vs Zombies VN Portable.exe"
        )
        assert(resolvedExe.lastPathComponent == "Plants Vs Zombies VN Portable.exe")
        assert(fm.fileExists(atPath: resolvedExe.path))
        let extractedDir = resolvedExe.deletingLastPathComponent()
        assert(fm.fileExists(atPath: extractedDir.appendingPathComponent("main.pak").path))
        assert(!fm.fileExists(atPath: extractedDir.appendingPathComponent("KillDuplicate.cmd").path), "KillDuplicate.cmd must be removed after extraction")

        // Simulate user creating a save file inside the extracted folder and verify second launch preserves it
        let saveFile = extractedDir.appendingPathComponent("userdata_save.dat")
        try Data("USER_PROGRESS_LEVEL_5".utf8).write(to: saveFile)
        try Data("@echo off".utf8).write(to: extractedDir.appendingPathComponent("KillDuplicate.cmd"))
        let secondResolved = try sessionMgr.preparePortableSession(
            for: outerExeURL,
            archiveOffset: tarOffset,
            runProgram: "Plants Vs Zombies VN Portable.exe"
        )
        assert(secondResolved == resolvedExe)
        assert(fm.fileExists(atPath: saveFile.path), "Second launch must reuse cached folder and preserve save files")

        print("ALL PORTABLE EXTRACTOR TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `test_portable_extractor.swift` to verify it fails**

Run:
```bash
swiftc Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Tests/test_portable_extractor.swift -o /tmp/test_portable_extractor
```
Expected: FAIL with `cannot find 'PortableExeExtractor' in scope`.

- [ ] **Step 3: Add `Equatable` to `PreparedSession` in `Sources/Core/SessionManager.swift` and implement `Sources/Core/PortableExeExtractor.swift`**

In `Sources/Core/SessionManager.swift:4`, change `public struct PreparedSession {` to `public struct PreparedSession: Equatable {`.

Create `Sources/Core/PortableExeExtractor.swift` implementing `PortableExtractorError`, `ExeExecutableKind`, `PortableExeExtractor`, and `PortableAppSessionManager`:
- `PortableExeExtractor.classify(data: Data) throws -> ExeExecutableKind`:
  1. Normalize `data` index to 0. If `try? ExeSwfExtractor.extract(from: data)` succeeds, return `.flash(payload)`.
  2. Guard `data.count >= 64`, `data[0] == 0x4D`, `data[1] == 0x5A` (`"MZ"`), else throw `PortableExtractorError.notAValidExecutable`.
  3. Search `data` in range `2..<data.count` for `sevenZipMagic = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])`. If found at `archiveOffset > 0`:
     - Search `0..<archiveOffset` for `;!@Install@!UTF-8!` and `;!@InstallEnd@!`, and pass that slice to `parseSfxRunProgram(from:)`.
     - Return `.sevenZipSfx(archiveOffset: archiveOffset, runProgram: runProgram)`.
  4. Otherwise return `.standaloneWin32`.
- `PortableExeExtractor.parseSfxRunProgram(from configData: Data) -> String?`:
  - Decode UTF-8 (with lossy fallback), find the line starting with `RunProgram=`, strip outer `"..."`, unescape `\"` to `"`, extract the executable token (if wrapped in `"..."`, take the first quoted string; otherwise take the trimmed string), strip any leading `%%T\\` or `%%T/`, normalize `\` to `/`, and return non-empty path.
- `PortableAppSessionManager`:
  - Default `portableRootURL`: `SessionManager.realUserHomeDirectory().appendingPathComponent("Library/Application Support/BugOnExe/PortableApps", isDirectory: true)`.
  - `preparePortableSession(for sourceExeURL: URL, archiveOffset: Int, runProgram: String?) throws -> URL`:
    1. Compute deterministic folder `<fnv1aHash>-<baseName>` under `portableRootURL`.
    2. Check `.extracted_ok` inside `sessionDir`: if it exists and the relative path stored inside it points to an existing file on disk, remove any stray `KillDuplicate.cmd` and return that URL immediately.
    3. Otherwise create `sessionDir`, slice `archiveOffset..<fileData.count` into `sessionDir.appendingPathComponent(".payload_archive.tmp")`, invoke `/usr/bin/tar -xf .payload_archive.tmp -C <sessionDir>`, remove `.payload_archive.tmp`, and delete `KillDuplicate.cmd` (case-insensitive check in `sessionDir`).
    4. Resolve inner `.exe` matching `runProgram` (exact relative path or case-insensitive filename match within up to 2 directory levels; fallback to the largest `.exe` in `sessionDir` whose name doesn't start with `unins` or `setup`).
    5. Write relative path to `.extracted_ok` and return the resolved `URL`.

- [ ] **Step 4: Run `test_portable_extractor.swift` to verify it passes**

Run:
```bash
swiftc Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/PortableExeExtractor.swift Tests/test_portable_extractor.swift -o /tmp/test_portable_extractor && /tmp/test_portable_extractor
```
Expected: PASS (`ALL PORTABLE EXTRACTOR TESTS PASSED`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/SessionManager.swift Sources/Core/PortableExeExtractor.swift Tests/test_portable_extractor.swift
git commit -m "feat(core): add PortableExeExtractor and persistent 7-Zip SFX session manager"
```

---

### Task 2: Bilingual Localization Keys & Wine Runtime Manager (`WineRuntimeManager.swift`)

**Files:**
- Modify: `Sources/Core/LocalizationManager.swift:25-240`
- Modify: `Resources/en.lproj/Localizable.strings:1-46`
- Modify: `Resources/vi.lproj/Localizable.strings:1-46`
- Create: `Sources/Core/WineRuntimeManager.swift`
- Modify: `Tests/test_localization.swift:1-60`
- Create: `Tests/test_wine_runtime.swift`

**Interfaces:**
- Consumes:
  - `SessionManager.realUserHomeDirectory() -> URL` (`Sources/Core/SessionManager.swift`)
  - `LocalizationManager.shared` (`Sources/Core/LocalizationManager.swift`)
- Produces:
  - New `L10nKey` cases in `LocalizationManager`:
    - `.alertWineRequiredTitle = "alert.wine_required.title"`
    - `.alertWineRequiredMessage = "alert.wine_required.message"`
    - `.alertWineInstallButton = "alert.wine_required.install_button"`
    - `.alertCancelButton = "alert.cancel_button"`
    - `.wineProgressWindowTitle = "wine.progress.window_title"`
    - `.wineProgressPreparing = "wine.progress.preparing"`
    - `.wineProgressDownloading = "wine.progress.downloading"`
    - `.wineProgressExtracting = "wine.progress.extracting"`
    - `.errorWineInstallFailed = "error.wine_install_failed"`
    - `.errorPortableExtractionFailed = "error.portable_extraction_failed"`
  - `public enum WineInstallStage: Equatable`:
    - `.preparing`
    - `.downloading(receivedBytes: Int64, expectedBytes: Int64)`
    - `.extracting`
  - `public enum WineRuntimeError: LocalizedError, Equatable`:
    - `.cancelled`
    - `.downloadFailed(String)`
    - `.extractionFailed(String)`
    - `.binaryNotFoundAfterInstall`
    - `.launchFailed(String)`
  - `public final class WineRuntimeManager`:
    - `public static let shared = WineRuntimeManager()`
    - `public static let fallbackDownloadURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-devel-11.21-osx64.tar.xz")!`
    - `public let runtimeRootURL: URL`
    - `public let winePrefixURL: URL`
    - `public init(runtimeRootURL: URL? = nil, winePrefixURL: URL? = nil, additionalSearchPaths: [URL]? = nil)`
    - `public func locateWineBinary() -> URL?`
    - `public func extractWineArchive(at archiveURL: URL) throws -> URL`
    - `public func buildLaunchProcess(exeURL: URL, wineBinaryURL: URL) throws -> Process`
    - `public func launchWindowsExecutable(exeURL: URL, wineBinaryURL: URL, completion: @escaping (Result<Void, Error>) -> Void)`
    - `@discardableResult public func downloadAndInstallWine(from overrideURL: URL? = nil, progressHandler: @escaping (WineInstallStage) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> URLSessionDownloadTask?`

- [ ] **Step 1: Add localization assertions in `Tests/test_localization.swift` and create `Tests/test_wine_runtime.swift`**

In `Tests/test_localization.swift`, add assertions before the final `print`:

```swift
manager.language = .english
assert(manager.string(.alertWineRequiredTitle).contains("Wine"))
assert(manager.string(.wineProgressDownloading, 50, 200, 25).contains("25%"))
manager.language = .vietnamese
assert(manager.string(.alertWineRequiredTitle).contains("Wine"))
assert(manager.string(.wineProgressDownloading, 50, 200, 25).contains("25%"))
```

Create `Tests/test_wine_runtime.swift`:

```swift
import Foundation

@main
struct WineRuntimeTestRunner {
    static func main() throws {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent("BugOnExeWineTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }

        let runtimeDir = tempRoot.appendingPathComponent("Runtime", isDirectory: true)
        let prefixDir = tempRoot.appendingPathComponent("WinePrefix", isDirectory: true)
        let mgr = WineRuntimeManager(runtimeRootURL: runtimeDir, winePrefixURL: prefixDir, additionalSearchPaths: [])

        // 1. When Runtime is empty and additionalSearchPaths is empty, locateWineBinary returns nil
        assert(mgr.locateWineBinary() == nil, "Expected nil when no Wine binary is installed")

        // 2. Stage a synthetic Wine Devel.app archive, extract via extractWineArchive, verify executable discovery
        let stageDir = tempRoot.appendingPathComponent("stage", isDirectory: true)
        let fakeWineBinDir = stageDir.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin", isDirectory: true)
        try fm.createDirectory(at: fakeWineBinDir, withIntermediateDirectories: true)
        let fakeWineBin = fakeWineBinDir.appendingPathComponent("wine")
        try "#!/bin/sh\nexit 0\n".data(using: .utf8)!.write(to: fakeWineBin)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeWineBin.path)

        let archiveURL = tempRoot.appendingPathComponent("wine-devel-test.tar.xz")
        let tarProc = Process()
        tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProc.currentDirectoryURL = stageDir
        tarProc.arguments = ["-cJf", archiveURL.path, "Wine Devel.app"]
        try tarProc.run()
        tarProc.waitUntilExit()
        assert(tarProc.terminationStatus == 0)

        let installedBin = try mgr.extractWineArchive(at: archiveURL)
        assert(installedBin.path == runtimeDir.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine").path)
        assert(mgr.locateWineBinary() == installedBin)

        // 3. Verify buildLaunchProcess sets currentDirectoryURL to the exe's parent folder and configures WINEPREFIX & WINEDEBUG
        let gameDir = tempRoot.appendingPathComponent("GameFolder", isDirectory: true)
        try fm.createDirectory(at: gameDir, withIntermediateDirectories: true)
        let gameExe = gameDir.appendingPathComponent("Plants Vs Zombies VN Portable.exe")
        try Data([0x4D, 0x5A]).write(to: gameExe)

        let proc = try mgr.buildLaunchProcess(exeURL: gameExe, wineBinaryURL: installedBin)
        assert(proc.executableURL == installedBin)
        assert(proc.currentDirectoryURL == gameDir, "Working directory must be game folder so DLLs and main.pak load")
        assert(proc.arguments == [gameExe.path])
        assert(proc.environment?["WINEPREFIX"] == prefixDir.path)
        assert(proc.environment?["WINEDEBUG"] == "-all")

        // 4. Verify downloadAndInstallWine from a local file:// URL updates progress stages and installs binary
        let runtimeDir2 = tempRoot.appendingPathComponent("Runtime2", isDirectory: true)
        let mgr2 = WineRuntimeManager(runtimeRootURL: runtimeDir2, winePrefixURL: prefixDir, additionalSearchPaths: [])
        var sawStages: [WineInstallStage] = []
        let sem = DispatchSemaphore(value: 0)
        var installResult: Result<URL, Error>?

        mgr2.downloadAndInstallWine(
            from: archiveURL,
            progressHandler: { stage in
                sawStages.append(stage)
            },
            completion: { result in
                installResult = result
                sem.signal()
            }
        )
        _ = sem.wait(timeout: .now() + 10.0)
        guard case .success(let finalBin) = installResult else {
            fatalError("Expected downloadAndInstallWine to succeed, got \(String(describing: installResult))")
        }
        assert(finalBin.path == runtimeDir2.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine").path)
        assert(sawStages.contains(.preparing))
        assert(sawStages.contains(.extracting))

        print("ALL WINE RUNTIME TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `test_localization` and `test_wine_runtime` to verify they fail**

Run:
```bash
swiftc Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization
```
Expected: FAIL with `type 'L10nKey' has no member 'alertWineRequiredTitle'`.

- [ ] **Step 3: Add new localization keys to `LocalizationManager.swift`, `Resources/en.lproj/Localizable.strings`, `Resources/vi.lproj/Localizable.strings` and implement `Sources/Core/WineRuntimeManager.swift`**

In `LocalizationManager.swift`, `Resources/en.lproj/Localizable.strings`, and `Resources/vi.lproj/Localizable.strings`, add:
- `alert.wine_required.title`:
  - EN: `"Additional Wine Runtime Required"`
  - VI: `"Cần tải thêm nhân tương thích Wine"`
- `alert.wine_required.message`:
  - EN: `"\"%@\" is a Windows application. Bug On EXE needs to download and install the Wine compatibility runtime (~200 MB) once to run Windows games and portable apps."`
  - VI: `"\"%@\" là ứng dụng/game Windows. Bug On EXE cần tải và cài đặt ngầm nhân tương thích Wine (~200 MB) một lần duy nhất để khởi chạy."`
- `alert.wine_required.install_button`:
  - EN: `"Download & Run"`
  - VI: `"Tải & Chạy ngay"`
- `alert.cancel_button`:
  - EN: `"Cancel"`
  - VI: `"Hủy"`
- `wine.progress.window_title`:
  - EN: `"Installing Wine Runtime"`
  - VI: `"Đang cài đặt nhân Wine"`
- `wine.progress.preparing`:
  - EN: `"Connecting to download server..."`
  - VI: `"Đang kết nối máy chủ tải xuống..."`
- `wine.progress.downloading`:
  - EN: `"Downloading Wine runtime: %d MB / %d MB (%d%%)"`
  - VI: `"Đang tải nhân Wine: %d MB / %d MB (%d%%)"`
- `wine.progress.extracting`:
  - EN: `"Extracting and configuring Wine runtime..."`
  - VI: `"Đang giải nén và cấu hình nhân Wine..."`
- `error.wine_install_failed`:
  - EN: `"Failed to install Wine runtime: %@"`
  - VI: `"Không thể cài đặt nhân Wine: %@"`
- `error.portable_extraction_failed`:
  - EN: `"Failed to unpack portable executable: %@"`
  - VI: `"Không thể giải nén gói ứng dụng portable: %@"`

Also update `.windowSubtitleFallback` and `.alertDefaultSetSuccessMessage` so they mention both Flash & Portable Windows `.exe` files without breaking any existing test assertions.

Create `Sources/Core/WineRuntimeManager.swift`:
- Default `runtimeRootURL`: `SessionManager.realUserHomeDirectory().appendingPathComponent("Library/Application Support/BugOnExe/Runtime", isDirectory: true)`
- Default `winePrefixURL`: `SessionManager.realUserHomeDirectory().appendingPathComponent("Library/Application Support/BugOnExe/WinePrefix", isDirectory: true)`
- Default `additionalSearchPaths` (when `nil` is passed to `init`):
  - `/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine`
  - `/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine`
  - `/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine`
  - `/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine`
  - `/opt/homebrew/bin/wine`, `/usr/local/bin/wine`, `/opt/homebrew/bin/wine64`, `/usr/local/bin/wine64`
- `locateWineBinary()`:
  - Checks inside `runtimeRootURL` for `Wine Devel.app`, `Wine Stable.app`, `Wine Staging.app`, `Wine Crossover.app` (`Contents/Resources/wine/bin/wine` then `wine64`), then iterates `additionalSearchPaths`, returning the first path where `FileManager.default.isExecutableFile(atPath:)` is true.
- `extractWineArchive(at archiveURL: URL) throws -> URL`:
  - Creates `runtimeRootURL`, runs `/usr/bin/tar -xf <archiveURL.path> -C <runtimeRootURL.path>`, runs `/usr/bin/xattr -cr <runtimeRootURL.path>`, and verifies `locateWineBinary()` returns a non-nil URL (else throws `WineRuntimeError.binaryNotFoundAfterInstall`).
- `buildLaunchProcess(exeURL: URL, wineBinaryURL: URL) throws -> Process`:
  - Creates `winePrefixURL` directory if needed, returns a `Process` with `executableURL = wineBinaryURL`, `arguments = [exeURL.path]`, `currentDirectoryURL = exeURL.deletingLastPathComponent()`, and environment merging `ProcessInfo.processInfo.environment` with `WINEPREFIX = winePrefixURL.path` and `WINEDEBUG = "-all"`.

- [ ] **Step 4: Run `test_localization` and `test_wine_runtime` to verify they pass**

Run:
```bash
swiftc Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization && /tmp/test_localization && \
swiftc Sources/Core/LocalizationManager.swift Sources/Core/SessionManager.swift Sources/Core/WineRuntimeManager.swift Tests/test_wine_runtime.swift -o /tmp/test_wine_runtime && /tmp/test_wine_runtime
```
Expected: PASS (`ALL LOCALIZATION TESTS PASSED` and `ALL WINE RUNTIME TESTS PASSED`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/LocalizationManager.swift Resources/en.lproj/Localizable.strings Resources/vi.lproj/Localizable.strings Sources/Core/WineRuntimeManager.swift Tests/test_localization.swift Tests/test_wine_runtime.swift
git commit -m "feat(wine): add WineRuntimeManager and bilingual localization strings"
```

---

### Task 3: In-App Wine Progress Window (`WineInstallProgressWindowController.swift`), Dual-Engine Routing in `ProjectorRunner` & Build Integration

**Files:**
- Create: `Sources/App/WineInstallProgressWindowController.swift`
- Modify: `Sources/App/ProjectorRunner.swift:1-128`
- Modify: `Sources/App/AppDelegate.swift:14-84`
- Modify: `scripts/build_app.sh:328-343`
- Modify: `Tests/test_projector_runner.swift:1-16`

**Interfaces:**
- Consumes:
  - `PortableExeExtractor`, `PortableAppSessionManager`, `ExeExecutableKind`, `PortableExtractorError` (`Sources/Core/PortableExeExtractor.swift`)
  - `WineRuntimeManager`, `WineInstallStage`, `WineRuntimeError` (`Sources/Core/WineRuntimeManager.swift`)
  - `LocalizationManager` (`Sources/Core/LocalizationManager.swift`)
- Produces:
  - `public final class WineInstallProgressWindowController: NSWindowController`:
    - `public var onCancel: (() -> Void)?`
    - `public init()`
    - `public func update(stage: WineInstallStage)`
  - `public enum ExecutionPlan: Equatable`:
    - `.flash(PreparedSession)`
    - `.windows(exeURL: URL, isExtractedFromSfx: Bool)`
  - `ProjectorRunner.prepareExecutionPlan(fileURL: URL, portableSessionManager: PortableAppSessionManager = PortableAppSessionManager()) throws -> ExecutionPlan`
  - Updated `ProjectorRunner.run(fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void)` supporting both `.flash` and `.windows` execution plans (with confirmation alert + `WineInstallProgressWindowController` when Wine is missing).

- [ ] **Step 1: Add dual-engine routing tests to `Tests/test_projector_runner.swift`**

Update `Tests/test_projector_runner.swift` to test both Flash (`prepareForLaunch` / `prepareExecutionPlan` -> `.flash`) and Portable 7z SFX / Win32 (`prepareExecutionPlan` -> `.windows`):

```swift
import Foundation

@main
struct ProjectorRunnerTest {
    static func main() throws {
        // 1. Existing IC3 Flash Projector .exe still prepares as Flash session
        let exeURL = URL(fileURLWithPath: "/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe")
        let session = try ProjectorRunner.prepareForLaunch(fileURL: exeURL)
        assert(FileManager.default.fileExists(atPath: session.swfFileURL.path))
        let recents = ProjectorRunner.recentFiles()
        assert(recents.first?.path == exeURL.path)

        let flashPlan = try ProjectorRunner.prepareExecutionPlan(fileURL: exeURL)
        if case .flash(let prepared) = flashPlan {
            assert(prepared.swfFileURL == session.swfFileURL)
        } else {
            fatalError("Expected .flash execution plan for IC3 exe")
        }

        // 2. Standalone Win32 PE32 prepares as .windows(exeURL, isExtractedFromSfx: false)
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("BugOnExeRunnerTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let winExe = tempDir.appendingPathComponent("stress.exe")
        var mzData = Data([0x4D, 0x5A, 0x90, 0x00])
        mzData.append(Data(repeating: 0x00, count: 128))
        try mzData.write(to: winExe)

        let portableMgr = PortableAppSessionManager(portableRootURL: tempDir.appendingPathComponent("PortableApps"))
        let winPlan = try ProjectorRunner.prepareExecutionPlan(fileURL: winExe, portableSessionManager: portableMgr)
        assert(winPlan == .windows(exeURL: winExe, isExtractedFromSfx: false))
        assert(ProjectorRunner.recentFiles().first?.path == winExe.path)

        // 3. Finder open disposition checks
        assert(AppDelegate.postFinderOpenDisposition(windowVisible: false, hadError: true) == .showLauncherWindow)
        assert(AppDelegate.postFinderOpenDisposition(windowVisible: false, hadError: false) == .terminate)
        assert(AppDelegate.postFinderOpenDisposition(windowVisible: true, hadError: true) == .keepOpen)
        print("ALL PROJECTOR RUNNER TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run `test_projector_runner.swift` to verify it fails**

Run:
```bash
swiftc Sources/Core/*.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_projector_runner.swift -o /tmp/test_projector_runner
```
Expected: FAIL with `type 'ProjectorRunner' has no member 'prepareExecutionPlan'`.

- [ ] **Step 3: Implement `Sources/App/WineInstallProgressWindowController.swift`, update `Sources/App/ProjectorRunner.swift`, and update `scripts/build_app.sh`**

1. Create `Sources/App/WineInstallProgressWindowController.swift`:
   - `NSWindow` (`440×150`, titled, closable: false during active install, centered) with title label (`L10nKey.wineProgressWindowTitle`), status label, `NSProgressIndicator` (bar style), and Cancel button (`L10nKey.alertCancelButton`).
   - `public func update(stage: WineInstallStage)` updates the progress bar (`isIndeterminate = true` for `.preparing` and `.extracting`; `isIndeterminate = false`, `minValue = 0`, `maxValue = 100` for `.downloading`) and localized status text.
2. In `Sources/App/ProjectorRunner.swift`:
   - Keep `prepareForLaunch(fileURL: URL) throws -> PreparedSession` intact for backward compatibility.
   - Add `public enum ExecutionPlan: Equatable { case flash(PreparedSession); case windows(exeURL: URL, isExtractedFromSfx: Bool) }`.
   - Implement `public static func prepareExecutionPlan(fileURL: URL, portableSessionManager: PortableAppSessionManager = PortableAppSessionManager()) throws -> ExecutionPlan`:
     - Calls `PortableExeExtractor.classify(fileURL: fileURL)`.
     - For `.flash(let payload)`: prepares session via `SessionManager().prepareSession(for: fileURL, payload: payload)`, records recent file, returns `.flash(session)`.
     - For `.sevenZipSfx(let archiveOffset, let runProgram)`: unpacks via `portableSessionManager.preparePortableSession(for: fileURL, archiveOffset: archiveOffset, runProgram: runProgram)`, records recent file, returns `.windows(exeURL: innerExe, isExtractedFromSfx: true)`.
     - For `.standaloneWin32`: records recent file, returns `.windows(exeURL: fileURL, isExtractedFromSfx: false)`.
   - In `ProjectorRunner.run(fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void)`:
     - Calls `prepareExecutionPlan(fileURL: fileURL)` on a background queue (so extracting a 35MB 7z SFX archive never freezes the main thread), then dispatches back to `.main`:
     - If `.flash(let session)`: launches via `Flash Player.app` as before.
     - If `.windows(let targetExeURL, _)`:
       - If `let wineBin = WineRuntimeManager.shared.locateWineBinary()`: calls `WineRuntimeManager.shared.launchWindowsExecutable(exeURL: targetExeURL, wineBinaryURL: wineBin, completion: completion)`.
       - If `locateWineBinary()` is `nil`: presents a localized `NSAlert` (`alertWineRequiredTitle`, `alertWineRequiredMessage` with `fileURL.lastPathComponent`, buttons `alertWineInstallButton` and `alertCancelButton`). If user cancels, completes with `.success(())`. If user clicks Install, shows `WineInstallProgressWindowController`, calls `WineRuntimeManager.shared.downloadAndInstallWine`, closes the progress window on finish, and on success launches `targetExeURL` via `launchWindowsExecutable`.
3. In `scripts/build_app.sh`:
   - Add `"$PROJ_ROOT/Sources/Core/PortableExeExtractor.swift"`, `"$PROJ_ROOT/Sources/Core/WineRuntimeManager.swift"`, and `"$PROJ_ROOT/Sources/App/WineInstallProgressWindowController.swift"` to the `swiftc` invocation.

- [ ] **Step 4: Build the app with `scripts/build_app.sh` and run all test suites to verify everything passes**

Run:
```bash
bash scripts/build_app.sh && \
swiftc Sources/Core/*.swift Sources/App/WineInstallProgressWindowController.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_projector_runner.swift -o /tmp/test_projector_runner && /tmp/test_projector_runner && \
swiftc Tests/test_bundle.swift -o /tmp/test_bundle && /tmp/test_bundle
```
Expected: PASS (`ALL PROJECTOR RUNNER TESTS PASSED` and `ALL BUNDLE VERIFICATION TESTS PASSED`).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/WineInstallProgressWindowController.swift Sources/App/ProjectorRunner.swift scripts/build_app.sh Tests/test_projector_runner.swift
git commit -m "feat(app): integrate Wine install progress UI and dual-engine EXE routing"
```
