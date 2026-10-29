import Foundation
import AppKit

@main
struct FallbackRoutingTestRunner {
    static func main() throws {
        // 1. Test OS version fallback decision
        assert(LauncherWindowController.shouldUseLiquidGlass(majorVersion: 26) == true, "macOS 26 should use Liquid Glass")
        assert(LauncherWindowController.shouldUseLiquidGlass(majorVersion: 27) == true, "macOS 27+ should use Liquid Glass")
        assert(LauncherWindowController.shouldUseLiquidGlass(majorVersion: 25) == false, "macOS 25 should fallback to standard UI")
        assert(LauncherWindowController.shouldUseLiquidGlass(majorVersion: 14) == false, "macOS 14 should fallback to standard UI")
        assert(LauncherWindowController.shouldUseLiquidGlass(majorVersion: 13) == false, "macOS 13 should fallback to standard UI")

        // 2. Test Store integration
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dummyExe = tempDir.appendingPathComponent("Sample_Test_App.exe")
        try Data([0x4D, 0x5A, 0x90]).write(to: dummyExe)

        let initialCount = ExeLibraryStore.shared.items.count
        ExeLibraryStore.shared.addOrUpdate(url: dummyExe)
        assert(ExeLibraryStore.shared.items.count == initialCount + 1, "Store should record newly opened exe file")

        // 3. Test window localization and live language switching in fallback mode
        LocalizationManager.shared.language = .english
        let controller = LauncherWindowController(majorVersion: 15)
        assert(controller.window?.title == "Bug On EXE")
        assert(controller.currentFallbackSubtitle.contains("Double-click any .exe file in Finder"))
        assert(controller.currentFallbackOpenButtonTitle == "Open Another .exe File...")
        LocalizationManager.shared.language = .vietnamese
        controller.applyLocalization()
        assert(controller.currentFallbackSubtitle.contains("Double-click trực tiếp vào file .exe"))
        assert(controller.currentFallbackOpenButtonTitle == "Mở file .exe khác...")
        LocalizationManager.shared.language = .english

        print("All Fallback routing tests passed successfully!")
    }
}
