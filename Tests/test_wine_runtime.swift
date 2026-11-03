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
        var installResult: Result<URL, Error>?

        mgr2.downloadAndInstallWine(
            from: archiveURL,
            progressHandler: { stage in
                sawStages.append(stage)
            },
            completion: { result in
                installResult = result
            }
        )
        let start1 = Date()
        while installResult == nil && Date().timeIntervalSince(start1) < 10.0 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        guard case .success(let finalBin) = installResult else {
            fatalError("Expected downloadAndInstallWine to succeed, got \(String(describing: installResult))")
        }
        assert(finalBin.path == runtimeDir2.appendingPathComponent("Wine Devel.app/Contents/Resources/wine/bin/wine").path)
        assert(sawStages.contains(.preparing))
        assert(sawStages.contains(.extracting))

        // 5. Verify cancel reports WineRuntimeError.cancelled and only completes once
        var cancelResults: [Result<URL, Error>] = []
        let dummyHTTPURL = URL(string: "http://127.0.0.1:9/dummy.tar.xz")!
        let cancelTask = mgr2.downloadAndInstallWine(
            from: dummyHTTPURL,
            progressHandler: { _ in },
            completion: { result in
                cancelResults.append(result)
            }
        )
        cancelTask?.cancel()
        let start2 = Date()
        while cancelResults.isEmpty && Date().timeIntervalSince(start2) < 5.0 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        assert(cancelResults.count == 1, "Must complete exactly once on cancellation")
        guard case .failure(let err) = cancelResults.first, let wineErr = err as? WineRuntimeError else {
            fatalError("Expected WineRuntimeError on cancel, got \(String(describing: cancelResults.first))")
        }
        assert(wineErr == .cancelled, "Expected .cancelled, got \(wineErr)")

        print("ALL WINE RUNTIME TESTS PASSED")
    }
}
