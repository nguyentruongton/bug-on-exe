import Foundation

@main
struct ProjectorRunnerTest {
    static func main() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("BugOnExeRunnerTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. Synthetic Flash Projector .exe prepares as Flash session
        let exeURL = tempDir.appendingPathComponent("MockFlashApp (GS6).exe")
        var syntheticData = Data([0x4D, 0x5A]) // PE MZ header
        syntheticData.append(contentsOf: [0x46, 0x57, 0x53, 0x09, 0x14, 0x00, 0x00, 0x00]) // FWS header
        syntheticData.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) // 12 payload bytes (total 20)
        syntheticData.append(contentsOf: [0x56, 0x34, 0x12, 0xFA]) // 0xFA123456
        let swfLen: UInt32 = 20
        withUnsafeBytes(of: swfLen.littleEndian) { syntheticData.append(contentsOf: $0) }
        try syntheticData.write(to: exeURL)

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
