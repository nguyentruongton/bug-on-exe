import Foundation

@main
struct CardGridViewTestRunner {
    static func main() throws {
        // 1. Test Filter Items by search query
        let item1 = ExeItem(name: "GS6_LV3_TESTING_01.exe", path: URL(fileURLWithPath: "/test/1.exe"), fileSizeFormatted: "5.4 MB", isPinned: true)
        let item2 = ExeItem(name: "Calculator_Flash.exe", path: URL(fileURLWithPath: "/test/2.exe"), fileSizeFormatted: "1.2 MB", isPinned: false)
        let item3 = ExeItem(name: "GS6_LV3_TRAINING_02.exe", path: URL(fileURLWithPath: "/test/3.exe"), fileSizeFormatted: "5.4 MB", isPinned: false)

        let all = [item1, item2, item3]

        assert(CardGridFormatters.filterItems(all, query: "").count == 3)
        assert(CardGridFormatters.filterItems(all, query: "gs6").count == 2)
        assert(CardGridFormatters.filterItems(all, query: "calc").first?.name == "Calculator_Flash.exe")
        assert(CardGridFormatters.filterItems(all, query: "nonexistent").isEmpty)

        // 2. Test SidebarFilter slicing + query
        let allSlice = CardGridFormatters.visibleItems(allItems: all, filter: .all, query: "")
        assert(allSlice.pinned.count == 1 && allSlice.recents.count == 2)

        let pinnedSlice = CardGridFormatters.visibleItems(allItems: all, filter: .pinned, query: "")
        assert(pinnedSlice.pinned.count == 1 && pinnedSlice.recents.isEmpty)

        let recentsSlice = CardGridFormatters.visibleItems(allItems: all, filter: .recents, query: "gs6")
        assert(recentsSlice.pinned.isEmpty && recentsSlice.recents.count == 1 && recentsSlice.recents[0].name == "GS6_LV3_TRAINING_02.exe")

        let noMatchSlice = CardGridFormatters.visibleItems(allItems: all, filter: .all, query: "no_such_file")
        assert(CardGridFormatters.shouldShowEmptySearchState(query: "no_such_file", pinned: noMatchSlice.pinned, recents: noMatchSlice.recents) == true)
        assert(CardGridFormatters.shouldShowEmptySearchState(query: "", pinned: [], recents: []) == false)
        assert(CardGridFormatters.shouldShowEmptySearchState(query: "gs6", pinned: allSlice.pinned, recents: allSlice.recents) == false)

        // 3. Test Relative Time Formatter in English (default) and Vietnamese
        let now = Date()
        assert(CardGridFormatters.relativeTimeString(from: now, relativeTo: now, language: .english) == "Just now")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-300), relativeTo: now, language: .english) == "5 min ago")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-7200), relativeTo: now, language: .english) == "2 hr ago")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-100000), relativeTo: now, language: .english) == "Yesterday")

        assert(CardGridFormatters.relativeTimeString(from: now, relativeTo: now, language: .vietnamese) == "Vừa mở")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-300), relativeTo: now, language: .vietnamese) == "5 phút trước")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-7200), relativeTo: now, language: .vietnamese) == "2 giờ trước")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-100000), relativeTo: now, language: .vietnamese) == "Hôm qua")

        // 4. Test ProjectorRunnerError localization in English and Vietnamese
        LocalizationManager.shared.language = .english
        assert(ProjectorRunnerError.projectorRuntimeMissing.errorDescription?.contains("Adobe Flash Player Projector runtime") == true)
        LocalizationManager.shared.language = .vietnamese
        assert(ProjectorRunnerError.projectorRuntimeMissing.errorDescription?.contains("Không tìm thấy nhân") == true)
        LocalizationManager.shared.language = .english

        print("All CardGrid tests passed successfully!")
    }
}
