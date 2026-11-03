import Foundation

@main
struct LocalizationTestRunner {
    static func main() throws {
        let suiteName = "test.localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. Default language is English even when unset or invalid
        let manager = LocalizationManager(defaults: defaults)
        assert(manager.language == .english, "Default language must be English")
        assert(manager.string(.toolbarAddFile) == "Add .exe File...")
        assert(manager.string(.sidebarItemAll) == "All Files")
        assert(manager.string(.timeMinutesAgo, 5) == "5 min ago")
        assert(manager.string(.alertOpenErrorTitle, "demo.exe") == "Cannot Open \"demo.exe\"")

        // 2. Corrupted UserDefaults value falls back to English
        defaults.set("fr_INVALID", forKey: "AppLanguage")
        let fallbackManager = LocalizationManager(defaults: defaults)
        assert(fallbackManager.language == .english, "Corrupted language key must fallback to English")

        // 3. Switch to Vietnamese updates strings and persists to UserDefaults
        manager.language = .vietnamese
        assert(defaults.string(forKey: "AppLanguage") == "vi")
        assert(manager.string(.toolbarAddFile) == "Thêm file .exe...")
        assert(manager.string(.sidebarItemAll) == "Tất cả file")
        assert(manager.string(.timeMinutesAgo, 5) == "5 phút trước")
        assert(manager.string(.alertOpenErrorTitle, "demo.exe") == "Không thể mở file \"demo.exe\"")

        // 4. Toggle helper cycles English <-> Vietnamese
        manager.toggleLanguage()
        assert(manager.language == .english)
        manager.toggleLanguage()
        assert(manager.language == .vietnamese)

        // 5. Every L10nKey has non-empty translations in both languages and uses "Bug On EXE"
        assert(manager.string(.windowTitleManager) == "Bug On EXE")
        assert(manager.string(.fallbackTitle) == "Bug On EXE")
        for lang in AppLanguage.allCases {
            manager.language = lang
            for key in L10nKey.allCases {
                let val = manager.string(key)
                assert(!val.isEmpty && val != key.rawValue, "Missing translation for \(key.rawValue) in \(lang.rawValue)")
                assert(!val.contains("Bug On Mac exe"), "Legacy brand name found in \(key.rawValue) (\(lang.rawValue)): \(val)")
            }
        }

        // 6. Wine runtime prompts and download progress strings
        manager.language = .english
        assert(manager.string(.alertWineRequiredTitle).contains("Wine"))
        assert(manager.string(.wineProgressDownloading, 50, 200, 25).contains("25%"))
        manager.language = .vietnamese
        assert(manager.string(.alertWineRequiredTitle).contains("Wine"))
        assert(manager.string(.wineProgressDownloading, 50, 200, 25).contains("25%"))

        // 7. Menu bar translations
        manager.language = .english
        assert(manager.string(.menuAppAbout) == "About Bug On EXE")
        assert(manager.string(.menuAppQuit) == "Quit Bug On EXE")
        assert(manager.string(.menuFile) == "File")
        assert(manager.string(.menuFileOpen) == "Open…")
        assert(manager.string(.menuEdit) == "Edit")
        assert(manager.string(.menuWindow) == "Window")

        manager.language = .vietnamese
        assert(manager.string(.menuAppAbout) == "Giới thiệu Bug On EXE")
        assert(manager.string(.menuAppQuit) == "Thoát Bug On EXE")
        assert(manager.string(.menuFile) == "Tệp")
        assert(manager.string(.menuFileOpen) == "Mở…")
        assert(manager.string(.menuEdit) == "Chỉnh sửa")
        assert(manager.string(.menuWindow) == "Cửa sổ")

        print("ALL LOCALIZATION TESTS PASSED")
    }
}
