import Foundation

@main
struct SessionTestRunner {
    static func main() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("BugOnMacExeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let cacheRoot = tempRoot.appendingPathComponent("Caches")
        let trustFile = tempRoot.appendingPathComponent("FlashPlayerTrust/BugOnMacExe.cfg")
        let manager = SessionManager(cacheRootURL: cacheRoot, trustConfigURL: trustFile)

        let sourceURL = tempRoot.appendingPathComponent("Mock IC3 (GS6)/Test_01.exe")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x4D, 0x5A]).write(to: sourceURL)
        let payload = SwfPayload(
            data: Data([0x46, 0x57, 0x53, 0x09, 0x14, 0x00, 0x00, 0x00]),
            signature: "FWS",
            version: 9,
            uncompressedLength: 20
        )

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
