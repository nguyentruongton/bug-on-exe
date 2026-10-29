import Foundation

@main
struct LibraryStoreTestRunner {
    static func main() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeFile = tempDir.appendingPathComponent("library_test.json")

        let store = ExeLibraryStore(storageURL: storeFile)

        // 1. Initially empty
        assert(store.items.isEmpty, "Initial items should be empty")
        assert(store.pinnedItems.isEmpty, "Initial pinned items should be empty")
        assert(store.recentItems.isEmpty, "Initial recent items should be empty")

        // 2. Add new file
        let dummyFile1 = tempDir.appendingPathComponent("Practice_Exam_01.exe")
        try Data([0x4D, 0x5A]).write(to: dummyFile1)
        store.addOrUpdate(url: dummyFile1)

        assert(store.items.count == 1, "Store should have 1 item")
        assert(store.recentItems.count == 1, "Recent items should have 1 item")
        assert(store.pinnedItems.isEmpty, "Pinned items should still be empty")
        let item1 = store.items[0]
        assert(item1.name == "Practice_Exam_01.exe", "Name should match")
        assert(item1.existsOnDisk == true, "File should exist on disk")

        // 3. Pin item
        store.togglePin(id: item1.id)
        assert(store.pinnedItems.count == 1, "Pinned items should have 1 item")
        assert(store.recentItems.isEmpty, "Recent items should be empty when pinned")

        // 4. Add another file
        let dummyFile2 = tempDir.appendingPathComponent("Tool_Game.exe")
        try Data([0x4D, 0x5A, 0x90]).write(to: dummyFile2)
        store.addOrUpdate(url: dummyFile2)
        assert(store.items.count == 2, "Store should have 2 items")
        assert(store.pinnedItems.count == 1, "Pinned should have 1")
        assert(store.recentItems.count == 1, "Recent should have 1")

        // 5. Update existing file does not duplicate
        store.addOrUpdate(url: dummyFile1)
        assert(store.items.count == 2, "Items count should still be 2 after re-adding existing file")
        assert(store.pinnedItems.count == 1, "Pinned count should still be 1")

        // 6. Persistence check - reload from disk
        let reloadedStore = ExeLibraryStore(storageURL: storeFile)
        assert(reloadedStore.items.count == 2, "Reloaded store should have 2 items")
        assert(reloadedStore.pinnedItems.count == 1, "Reloaded pinned count should be 1")

        // 7. Clear recents
        reloadedStore.clearRecents()
        assert(reloadedStore.pinnedItems.count == 1, "Pinned items must be preserved after clearRecents")
        assert(reloadedStore.recentItems.isEmpty, "Recents should be empty after clearRecents")

        // 8. Missing files check
        try FileManager.default.removeItem(at: dummyFile1)
        assert(reloadedStore.items[0].existsOnDisk == false, "Deleted file should report existsOnDisk == false")

        reloadedStore.cleanMissingFiles()
        assert(reloadedStore.items.isEmpty, "cleanMissingFiles should remove missing entries")

        // 9. Validation of file extensions
        assert(ExeLibraryStore.isValidExecutable(url: URL(fileURLWithPath: "/test/app.exe")) == true)
        assert(ExeLibraryStore.isValidExecutable(url: URL(fileURLWithPath: "/test/game.SWF")) == true)
        assert(ExeLibraryStore.isValidExecutable(url: URL(fileURLWithPath: "/test/doc.pdf")) == false)
        assert(ExeLibraryStore.isValidExecutable(url: URL(fileURLWithPath: "/test/image.png")) == false)

        // 10. Max 20-file cap on recentItems
        for i in 1...25 {
            let f = tempDir.appendingPathComponent("file_\(i).exe")
            try Data([0x4D]).write(to: f)
            reloadedStore.addOrUpdate(url: f)
        }
        assert(reloadedStore.recentItems.count == 20, "recentItems must be capped at 20 items, got \(reloadedStore.recentItems.count)")

        print("All ExeLibraryStore tests passed successfully!")
    }
}
