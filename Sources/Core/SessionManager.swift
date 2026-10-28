import Foundation

public struct PreparedSession {
    public let sessionDirectory: URL
    public let swfFileURL: URL
    public let trustConfigURL: URL
}

public final class SessionManager {
    public let cacheRootURL: URL
    public let trustConfigURL: URL

    public init(cacheRootURL: URL? = nil, trustConfigURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheRootURL = cacheRootURL ?? home
            .appendingPathComponent("Library/Caches/BugOnMacExe/Sessions", isDirectory: true)
        self.trustConfigURL = trustConfigURL ?? home
            .appendingPathComponent("Library/Preferences/Macromedia/Flash Player/#Security/FlashPlayerTrust/BugOnMacExe.cfg", isDirectory: false)
    }

    public func prepareSession(for sourceExeURL: URL, payload: SwfPayload) throws -> PreparedSession {
        let fm = FileManager.default
        let baseName = sourceExeURL.deletingPathExtension().lastPathComponent
        let pathHash = Self.fnv1aHashHex(sourceExeURL.standardizedFileURL.path)
        let sessionDir = cacheRootURL.appendingPathComponent("\(pathHash)-\(baseName)", isDirectory: true)

        try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let swfFileURL = sessionDir.appendingPathComponent("\(baseName).swf", isDirectory: false)
        try payload.data.write(to: swfFileURL, options: .atomic)

        // Symlink non-.exe sibling items so relative asset loads succeed
        let parentDir = sourceExeURL.deletingLastPathComponent()
        if let siblings = try? fm.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for sibling in siblings {
                let ext = sibling.pathExtension.lowercased()
                if ext == "exe" || sibling.lastPathComponent == swfFileURL.lastPathComponent {
                    continue
                }
                let linkURL = sessionDir.appendingPathComponent(sibling.lastPathComponent)
                if !fm.fileExists(atPath: linkURL.path) {
                    try? fm.createSymbolicLink(at: linkURL, withDestinationURL: sibling)
                }
            }
        }

        try ensureTrustedPaths([
            cacheRootURL.path,
            sessionDir.path,
            parentDir.path
        ])

        return PreparedSession(
            sessionDirectory: sessionDir,
            swfFileURL: swfFileURL,
            trustConfigURL: trustConfigURL
        )
    }

    private func ensureTrustedPaths(_ paths: [String]) throws {
        let fm = FileManager.default
        let trustDir = trustConfigURL.deletingLastPathComponent()
        try fm.createDirectory(at: trustDir, withIntermediateDirectories: true)

        var existingLines: [String] = []
        if let existing = try? String(contentsOf: trustConfigURL, encoding: .utf8) {
            existingLines = existing
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        var changed = false
        for path in paths where !existingLines.contains(path) {
            existingLines.append(path)
            changed = true
        }

        if changed || !fm.fileExists(atPath: trustConfigURL.path) {
            let output = existingLines.joined(separator: "\n") + "\n"
            try output.write(to: trustConfigURL, atomically: true, encoding: .utf8)
        }
    }

    private static func fnv1aHashHex(_ string: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
    }
}
