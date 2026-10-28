import Foundation

@main
struct ProjectorRunnerTest {
    static func main() throws {
        let exeURL = URL(fileURLWithPath: "/Users/stark/Documents/IC3/GS6 Level 3/GS6_LV3_TESTING_01_(2526GM).exe")
        let session = try ProjectorRunner.prepareForLaunch(fileURL: exeURL)
        assert(FileManager.default.fileExists(atPath: session.swfFileURL.path))
        let recents = ProjectorRunner.recentFiles()
        assert(recents.first?.path == exeURL.path)
        print("ALL PROJECTOR RUNNER TESTS PASSED")
    }
}
