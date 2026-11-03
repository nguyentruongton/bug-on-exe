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
