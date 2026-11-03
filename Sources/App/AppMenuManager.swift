import Foundation
import AppKit
import Combine

public final class AppMenuManager: NSObject {
    public static let shared = AppMenuManager()

    private var cancellables = Set<AnyCancellable>()
    private var localizedItems: [(item: NSMenuItem, key: L10nKey)] = []
    private var localizedMenus: [(menu: NSMenu, key: L10nKey)] = []
    private var isSetup = false

    public override init() {
        super.init()
    }

    public func setupMenu() {
        guard !isSetup else {
            updateLocalizedTitles()
            return
        }
        isSetup = true

        let mainMenu = NSMenu()
        localizedItems.removeAll()
        localizedMenus.removeAll()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let aboutItem = NSMenuItem(title: "", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        aboutItem.target = NSApp
        register(item: aboutItem, key: .menuAppAbout)
        appMenu.addItem(aboutItem)

        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        register(item: hideItem, key: .menuAppHide)
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        hideOthersItem.target = NSApp
        register(item: hideOthersItem, key: .menuAppHideOthers)
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        register(item: showAllItem, key: .menuAppShowAll)
        appMenu.addItem(showAllItem)

        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        register(item: quitItem, key: .menuAppQuit)
        appMenu.addItem(quitItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu()
        register(item: fileMenuItem, key: .menuFile)
        register(menu: fileMenu, key: .menuFile)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let openItem = NSMenuItem(title: "", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        // Target is nil to allow responder chain forwarding to AppDelegate or active controller
        register(item: openItem, key: .menuFileOpen)
        fileMenu.addItem(openItem)

        let closeItem = NSMenuItem(title: "", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        register(item: closeItem, key: .menuFileCloseWindow)
        fileMenu.addItem(closeItem)

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu()
        register(item: editMenuItem, key: .menuEdit)
        register(menu: editMenu, key: .menuEdit)
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let undoItem = NSMenuItem(title: "", action: Selector(("undo:")), keyEquivalent: "z")
        register(item: undoItem, key: .menuEditUndo)
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        register(item: redoItem, key: .menuEditRedo)
        editMenu.addItem(redoItem)

        editMenu.addItem(NSMenuItem.separator())

        let cutItem = NSMenuItem(title: "", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        register(item: cutItem, key: .menuEditCut)
        editMenu.addItem(cutItem)

        let copyItem = NSMenuItem(title: "", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        register(item: copyItem, key: .menuEditCopy)
        editMenu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        register(item: pasteItem, key: .menuEditPaste)
        editMenu.addItem(pasteItem)

        let selectAllItem = NSMenuItem(title: "", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        register(item: selectAllItem, key: .menuEditSelectAll)
        editMenu.addItem(selectAllItem)

        // 4. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu()
        register(item: windowMenuItem, key: .menuWindow)
        register(menu: windowMenu, key: .menuWindow)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        let minimizeItem = NSMenuItem(title: "", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        register(item: minimizeItem, key: .menuWindowMinimize)
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: "", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        register(item: zoomItem, key: .menuWindowZoom)
        windowMenu.addItem(zoomItem)

        windowMenu.addItem(NSMenuItem.separator())

        let bringAllItem = NSMenuItem(title: "", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        register(item: bringAllItem, key: .menuWindowBringAllToFront)
        windowMenu.addItem(bringAllItem)

        NSApp.windowsMenu = windowMenu

        // Subscribe to dynamic language updates
        LocalizationManager.shared.$language
            .sink { [weak self] newLang in
                if Thread.isMainThread {
                    self?.updateLocalizedTitles(language: newLang)
                } else {
                    DispatchQueue.main.async {
                        self?.updateLocalizedTitles(language: newLang)
                    }
                }
            }
            .store(in: &cancellables)

        updateLocalizedTitles()
        NSApp.mainMenu = mainMenu
    }

    private func register(item: NSMenuItem, key: L10nKey) {
        localizedItems.append((item: item, key: key))
    }

    private func register(menu: NSMenu, key: L10nKey) {
        localizedMenus.append((menu: menu, key: key))
    }

    public func updateLocalizedTitles(language: AppLanguage? = nil) {
        let lang = language ?? LocalizationManager.shared.language
        let l10n = LocalizationManager.shared
        for entry in localizedItems {
            entry.item.title = l10n.string(entry.key, language: lang)
        }
        for entry in localizedMenus {
            entry.menu.title = l10n.string(entry.key, language: lang)
        }
    }
}
