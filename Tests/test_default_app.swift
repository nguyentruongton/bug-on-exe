import Foundation

@main
struct DefaultAppTestRunner {
    static func main() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("BugOnExeDefaultAppTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        for i in 1...4 {
            let dummy = tempDir.appendingPathComponent("TestApp_\(i).exe")
            try Data([0x4D, 0x5A]).write(to: dummy)
        }

        let discovered = DefaultAppManager.discoverExeFiles(in: tempDir)
        assert(discovered.count >= 4, "Should discover at least the 4 dummy .exe files")
        assert(discovered.first?.pathExtension.lowercased() == "exe")
        _ = DefaultAppManager.isDefaultHandlerForExe()
        assert(
            DefaultAppManager.matchesBundleIdentifier("com.stark.bugonmacexe", primaryHandler: "com.stark.bugonmacexe", fallbackHandlers: ["com.apple.TextEdit"]) == true
        )
        assert(
            DefaultAppManager.matchesBundleIdentifier("com.stark.bugonmacexe", primaryHandler: "com.aone.keka", fallbackHandlers: ["com.stark.bugonmacexe"]) == false,
            "Must not report default handler when primary .exe UTI is owned by another app"
        )
        print("ALL DEFAULT APP TESTS PASSED")
    }
}
