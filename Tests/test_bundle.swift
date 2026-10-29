import Foundation
import AppKit

@main
struct BundleVerificationTest {
    static func main() throws {
        let fm = FileManager.default
        let legacyURL = URL(fileURLWithPath: "/Applications/Bug On Mac exe.app")
        assert(!fm.fileExists(atPath: legacyURL.path), "Legacy /Applications/Bug On Mac exe.app must be removed")

        let appURL = URL(fileURLWithPath: "/Applications/Bug On EXE.app")
        assert(fm.fileExists(atPath: appURL.path), "Installed app bundle must exist at /Applications/Bug On EXE.app")

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any]
        assert(plist?["CFBundleIdentifier"] as? String == "com.stark.bugonmacexe")
        assert(plist?["CFBundleDisplayName"] as? String == "Bug On EXE")
        assert(plist?["CFBundleName"] as? String == "Bug On EXE")
        assert(plist?["CFBundleDevelopmentRegion"] as? String == "en", "Default development region must be English (en)")
        let localizations = plist?["CFBundleLocalizations"] as? [String] ?? []
        assert(localizations.contains("en") && localizations.contains("vi"), "Bundle must declare en and vi localizations")

        for lang in ["en", "vi"] {
            let stringsURL = appURL.appendingPathComponent("Contents/Resources/\(lang).lproj/Localizable.strings")
            assert(fm.fileExists(atPath: stringsURL.path), "\(lang).lproj/Localizable.strings must be bundled")
            let data = try Data(contentsOf: stringsURL)
            let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String]
            assert(dict?["window.title.manager"] == "Bug On EXE", "\(lang) strings must define Bug On EXE title")
        }

        let icnsURL = appURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let icnsAttr = try fm.attributesOfItem(atPath: icnsURL.path)
        let icnsSize = (icnsAttr[.size] as? NSNumber)?.intValue ?? 0
        assert(icnsSize > 10_000, "AppIcon.icns must be non-empty and multi-resolution (got \(icnsSize) bytes)")

        let previewURL = URL(fileURLWithPath: "Resources/AppIcon-Preview.png")
        assert(fm.fileExists(atPath: previewURL.path), "Resources/AppIcon-Preview.png must exist for README")
        let previewData = try Data(contentsOf: previewURL)
        guard let rep = NSBitmapImageRep(data: previewData) else {
            fatalError("Unable to decode Resources/AppIcon-Preview.png")
        }
        assert(rep.pixelsWide == 512 && rep.pixelsHigh == 512, "Preview icon must be 512x512")
        // Verify Apple HIG squircle outer margin: pixel (2, 2) must be completely transparent
        let cornerColor = rep.colorAt(x: 2, y: 2)
        assert((cornerColor?.alphaComponent ?? 1.0) < 0.01, "Outer corner of icon canvas must be transparent per Apple HIG squircle grid")
        // Center pixel must be opaque
        let centerColor = rep.colorAt(x: 256, y: 256)
        assert((centerColor?.alphaComponent ?? 0.0) > 0.95, "Center of icon must be opaque")

        let execURL = appURL.appendingPathComponent("Contents/MacOS/BugOnMacExe")
        assert(fm.isExecutableFile(atPath: execURL.path), "Main executable must exist and be executable")

        let projectorExecURL = appURL.appendingPathComponent("Contents/Resources/Flash Player.app/Contents/MacOS/Flash Player")
        assert(fm.isExecutableFile(atPath: projectorExecURL.path), "Bundled 64-bit Flash Player executable must exist")

        print("ALL BUNDLE VERIFICATION TESTS PASSED")
    }
}
