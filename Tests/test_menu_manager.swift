import Foundation
import AppKit

@main
struct MenuManagerTestRunner {
    static func main() {
        let app = NSApplication.shared
        let manager = AppMenuManager.shared
        manager.setupMenu()

        guard let mainMenu = app.mainMenu else {
            fatalError("mainMenu must not be nil")
        }
        assert(mainMenu.items.count == 4, "Expected 4 top-level menus, found \(mainMenu.items.count)")

        // Check English initial titles
        LocalizationManager.shared.language = .english
        manager.updateLocalizedTitles()
        assert(mainMenu.items[0].submenu?.items.first?.title == "About Bug On EXE", "Actual: \(String(describing: mainMenu.items[0].submenu?.items.first?.title))")
        assert(mainMenu.items[1].title == "File", "Actual: \(mainMenu.items[1].title)")
        assert(mainMenu.items[2].title == "Edit", "Actual: \(mainMenu.items[2].title)")
        assert(mainMenu.items[3].title == "Window", "Actual: \(mainMenu.items[3].title)")

        // Check key equivalents
        let fileSubmenu = mainMenu.items[1].submenu!
        let openItem = fileSubmenu.items.first(where: { $0.action == #selector(NSDocumentController.openDocument(_:)) })
        assert(openItem?.keyEquivalent == "o", "Open shortcut must be Cmd+o")

        let appSubmenu = mainMenu.items[0].submenu!
        let quitItem = appSubmenu.items.first(where: { $0.action == #selector(NSApplication.terminate(_:)) })
        assert(quitItem?.keyEquivalent == "q", "Quit shortcut must be Cmd+q")

        let editSubmenu = mainMenu.items[2].submenu!
        let copyItem = editSubmenu.items.first(where: { $0.action == #selector(NSText.copy(_:)) })
        assert(copyItem?.keyEquivalent == "c", "Copy shortcut must be Cmd+c")

        let windowSubmenu = mainMenu.items[3].submenu!
        let minimizeItem = windowSubmenu.items.first(where: { $0.action == #selector(NSWindow.performMiniaturize(_:)) })
        assert(minimizeItem?.keyEquivalent == "m", "Minimize shortcut must be Cmd+m")

        // Check Vietnamese dynamic update
        LocalizationManager.shared.language = .vietnamese
        assert(mainMenu.items[0].submenu?.items.first?.title == "Giới thiệu Bug On EXE", "Actual: \(String(describing: mainMenu.items[0].submenu?.items.first?.title))")
        assert(mainMenu.items[1].title == "Tệp", "Actual: \(mainMenu.items[1].title)")
        assert(mainMenu.items[2].title == "Chỉnh sửa", "Actual: \(mainMenu.items[2].title)")
        assert(mainMenu.items[3].title == "Cửa sổ", "Actual: \(mainMenu.items[3].title)")

        print("ALL MENU MANAGER TESTS PASSED")
    }
}
