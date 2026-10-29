import Foundation

@main
struct BundleVerificationTest {
    static func main() throws {
        let appURL = URL(fileURLWithPath: "/Applications/Bug On Mac exe.app")
        let fm = FileManager.default
        assert(fm.fileExists(atPath: appURL.path), "Installed app bundle must exist at /Applications/Bug On Mac exe.app")

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        assert(plist?["CFBundleIdentifier"] as? String == "com.stark.bugonmacexe")
        assert(plist?["CFBundleDisplayName"] as? String == "Bug On Mac exe")
        assert(plist?["CFBundleDevelopmentRegion"] as? String == "en", "Default development region must be English (en)")
        let localizations = plist?["CFBundleLocalizations"] as? [String] ?? []
        assert(localizations.contains("en") && localizations.contains("vi"), "Bundle must declare en and vi localizations")

        let enStrings = appURL.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings")
        let viStrings = appURL.appendingPathComponent("Contents/Resources/vi.lproj/Localizable.strings")
        assert(fm.fileExists(atPath: enStrings.path), "en.lproj/Localizable.strings must be bundled")
        assert(fm.fileExists(atPath: viStrings.path), "vi.lproj/Localizable.strings must be bundled")

        let execURL = appURL.appendingPathComponent("Contents/MacOS/BugOnMacExe")
        assert(fm.isExecutableFile(atPath: execURL.path), "Main executable must exist and be executable")

        let projectorExecURL = appURL.appendingPathComponent("Contents/Resources/Flash Player.app/Contents/MacOS/Flash Player")
        assert(fm.isExecutableFile(atPath: projectorExecURL.path), "Bundled 64-bit Flash Player executable must exist")

        print("ALL BUNDLE VERIFICATION TESTS PASSED")
    }
}
