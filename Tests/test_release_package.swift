import Foundation

@main
struct ReleasePackageTest {
    static func main() throws {
        let fm = FileManager.default
        let zipURL = URL(fileURLWithPath: "dist/Bug-On-EXE-macOS.zip")
        let dmgURL = URL(fileURLWithPath: "dist/Bug-On-EXE-macOS.dmg")
        let readmeURL = URL(fileURLWithPath: "README.md")
        let workflowURL = URL(fileURLWithPath: ".github/workflows/release.yml")

        assert(fm.fileExists(atPath: zipURL.path), "Release ZIP must exist at dist/Bug-On-EXE-macOS.zip")
        assert(fm.fileExists(atPath: dmgURL.path), "Release DMG must exist at dist/Bug-On-EXE-macOS.dmg")
        assert(fm.fileExists(atPath: readmeURL.path), "README.md must exist")
        assert(fm.fileExists(atPath: workflowURL.path), ".github/workflows/release.yml must exist")

        let readme = try String(contentsOf: readmeURL, encoding: .utf8)
        assert(readme.contains("Bug On EXE"), "README.md must document Bug On EXE")
        assert(readme.contains("Resources/AppIcon-Preview.png"), "README.md must embed AppIcon-Preview.png")
        assert(readme.contains("xattr -cr"), "README.md must include Gatekeeper quarantine removal tip")

        // Verify extracting the ZIP with ditto preserves executable bit and code signature
        let extractDir = fm.temporaryDirectory.appendingPathComponent("BugOnExeZipVerify-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: extractDir) }
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zipURL.path, extractDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        assert(unzip.terminationStatus == 0, "ditto -x -k must succeed")

        let extractedApp = extractDir.appendingPathComponent("Bug On EXE.app")
        let extractedExec = extractedApp.appendingPathComponent("Contents/MacOS/BugOnMacExe")
        let extractedFlash = extractedApp.appendingPathComponent("Contents/Resources/Flash Player.app/Contents/MacOS/Flash Player")
        assert(fm.isExecutableFile(atPath: extractedExec.path), "Extracted main binary must be executable")
        assert(fm.isExecutableFile(atPath: extractedFlash.path), "Extracted Flash Player binary must be executable")

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--deep", "--strict", extractedApp.path]
        try codesign.run()
        codesign.waitUntilExit()
        assert(codesign.terminationStatus == 0, "Extracted Bug On EXE.app must pass codesign --verify --deep --strict")

        print("ALL RELEASE PACKAGE TESTS PASSED")
    }
}
