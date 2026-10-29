import Foundation
import Combine

public struct ExeItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public let name: String
    public let path: URL
    public var fileSizeFormatted: String
    public var lastOpened: Date
    public var isPinned: Bool

    public var existsOnDisk: Bool {
        return FileManager.default.fileExists(atPath: path.path)
    }

    public init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        fileSizeFormatted: String,
        lastOpened: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.fileSizeFormatted = fileSizeFormatted
        self.lastOpened = lastOpened
        self.isPinned = isPinned
    }
}

public final class ExeLibraryStore: ObservableObject {
    public static let shared = ExeLibraryStore()

    @Published public private(set) var items: [ExeItem] = []

    private let storageURL: URL

    public static func isValidExecutable(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "exe" || ext == "swf"
    }

    public var pinnedItems: [ExeItem] {
        return items.filter { $0.isPinned }.sorted { $0.lastOpened > $1.lastOpened }
    }

    public var recentItems: [ExeItem] {
        let unpinned = items.filter { !$0.isPinned }.sorted { $0.lastOpened > $1.lastOpened }
        return Array(unpinned.prefix(20))
    }

    public init(storageURL: URL? = nil) {
        if let customURL = storageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("BugOnMacExe", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.storageURL = dir.appendingPathComponent("library.json")
        }
        loadItems()
    }

    private func loadItems() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ExeItem].self, from: data) else {
            self.items = []
            return
        }
        self.items = decoded
    }

    private func saveItems() {
        guard let data = try? JSONEncoder().encode(self.items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    public func addOrUpdate(url: URL, isPinned: Bool? = nil) {
        if Thread.isMainThread {
            _addOrUpdate(url: url, isPinned: isPinned)
        } else {
            DispatchQueue.main.sync {
                self._addOrUpdate(url: url, isPinned: isPinned)
            }
        }
    }

    private func _addOrUpdate(url: URL, isPinned: Bool? = nil) {
        let standardizedURL = url.standardizedFileURL
        guard Self.isValidExecutable(url: standardizedURL) else { return }

        let fileName = standardizedURL.lastPathComponent
        let fileSize = formatFileSize(url: standardizedURL)

        if let index = items.firstIndex(where: { $0.path.standardizedFileURL.path == standardizedURL.path }) {
            var existing = items[index]
            existing.fileSizeFormatted = fileSize
            existing.lastOpened = Date()
            if let pinned = isPinned {
                existing.isPinned = pinned
            }
            items[index] = existing
        } else {
            let newItem = ExeItem(
                id: UUID(),
                name: fileName,
                path: standardizedURL,
                fileSizeFormatted: fileSize,
                lastOpened: Date(),
                isPinned: isPinned ?? false
            )
            items.append(newItem)
        }
        saveItems()
    }

    public func togglePin(id: UUID) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.togglePin(id: id) }
            return
        }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        saveItems()
    }

    public func remove(id: UUID) {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.remove(id: id) }
            return
        }
        items.removeAll(where: { $0.id == id })
        saveItems()
    }

    public func clearRecents() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.clearRecents() }
            return
        }
        items.removeAll(where: { !$0.isPinned })
        saveItems()
    }

    public func cleanMissingFiles() {
        if !Thread.isMainThread {
            DispatchQueue.main.sync { self.cleanMissingFiles() }
            return
        }
        items.removeAll(where: { !$0.existsOnDisk })
        saveItems()
    }

    private func formatFileSize(url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "0 KB"
        }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        bcf.countStyle = .file
        return bcf.string(fromByteCount: size)
    }
}
