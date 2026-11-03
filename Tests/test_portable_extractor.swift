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
