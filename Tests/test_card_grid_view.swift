import Foundation

@main
struct CardGridViewTestRunner {
    static func main() throws {
        // 1. Test Filter Items
        let item1 = ExeItem(name: "GS6_LV3_TESTING_01.exe", path: URL(fileURLWithPath: "/test/1.exe"), fileSizeFormatted: "5.4 MB")
        let item2 = ExeItem(name: "Calculator_Flash.exe", path: URL(fileURLWithPath: "/test/2.exe"), fileSizeFormatted: "1.2 MB")
        let item3 = ExeItem(name: "GS6_LV3_TRAINING_02.exe", path: URL(fileURLWithPath: "/test/3.exe"), fileSizeFormatted: "5.4 MB")

        let all = [item1, item2, item3]

        let filterEmpty = CardGridFormatters.filterItems(all, query: "")
        assert(filterEmpty.count == 3, "Empty query should return all items")

        let filterGS6 = CardGridFormatters.filterItems(all, query: "gs6")
        assert(filterGS6.count == 2, "Query 'gs6' should return 2 items")

        let filterCalc = CardGridFormatters.filterItems(all, query: "calc")
        assert(filterCalc.count == 1 && filterCalc[0].name == "Calculator_Flash.exe", "Query 'calc' should match item2")

        let filterNone = CardGridFormatters.filterItems(all, query: "nonexistent")
        assert(filterNone.isEmpty, "Query nonexistent should return empty")

        // 2. Test Relative Time Formatter
        let now = Date()
        let justNow = CardGridFormatters.relativeTimeString(from: now, relativeTo: now)
        assert(justNow == "Vừa mở", "Relative time for now should be 'Vừa mở'")

        let fiveMinsAgo = now.addingTimeInterval(-300)
        let fiveMins = CardGridFormatters.relativeTimeString(from: fiveMinsAgo, relativeTo: now)
        assert(fiveMins == "5 phút trước", "5 mins ago should be '5 phút trước'")

        let twoHoursAgo = now.addingTimeInterval(-7200)
        let twoHours = CardGridFormatters.relativeTimeString(from: twoHoursAgo, relativeTo: now)
        assert(twoHours == "2 giờ trước", "2 hours ago should be '2 giờ trước'")

        print("All CardGrid tests passed successfully!")
    }
}
