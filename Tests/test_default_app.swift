import Foundation

@main
struct DefaultAppTestRunner {
    static func main() throws {
        let ic3Root = URL(fileURLWithPath: "/Users/stark/Documents/IC3")
        let discovered = DefaultAppManager.discoverExeFiles(in: ic3Root)
        assert(discovered.count >= 4, "Should discover at least the 4 GS6 Level 3 .exe files")
        assert(discovered.first?.pathExtension.lowercased() == "exe")
        _ = DefaultAppManager.isDefaultHandlerForExe()
        print("ALL DEFAULT APP TESTS PASSED")
    }
}
