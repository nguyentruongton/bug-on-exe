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
