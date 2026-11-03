import Foundation
import Darwin

public struct PreparedSession: Equatable {
    public let sessionDirectory: URL
    public let swfFileURL: URL
    public let trustConfigURL: URL
}

public final class SessionManager {
    public let cacheRootURL: URL
    public let trustConfigURL: URL
    private let mirrorTrustConfigURL: URL?

    public static func realUserHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public init(cacheRootURL: URL? = nil, trustConfigURL: URL? = nil) {
        let realHome = Self.realUserHomeDirectory()
        let envHome = FileManager.default.homeDirectoryForCurrentUser
        let defaultCache = realHome.appendingPathComponent("Library/Caches/BugOnMacExe/Sessions", isDirectory: true)
        let defaultTrust = realHome.appendingPathComponent("Library/Preferences/Macromedia/Flash Player/#Security/FlashPlayerTrust/BugOnMacExe.cfg", isDirectory: false)

        self.cacheRootURL = cacheRootURL ?? defaultCache
        self.trustConfigURL = trustConfigURL ?? defaultTrust

        if trustConfigURL == nil && envHome.standardizedFileURL.path != realHome.standardizedFileURL.path {
            self.mirrorTrustConfigURL = envHome.appendingPathComponent("Library/Preferences/Macromedia/Flash Player/#Security/FlashPlayerTrust/BugOnMacExe.cfg", isDirectory: false)
        } else {
            self.mirrorTrustConfigURL = nil
        }
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

        let trustedPaths = [
            cacheRootURL.path,
            sessionDir.path,
            parentDir.path
        ]
        try Self.writeTrustFile(at: trustConfigURL, paths: trustedPaths)
        if let mirror = mirrorTrustConfigURL {
            try? Self.writeTrustFile(at: mirror, paths: trustedPaths)
        }

        return PreparedSession(
            sessionDirectory: sessionDir,
            swfFileURL: swfFileURL,
            trustConfigURL: trustConfigURL
        )
    }

    private static func writeTrustFile(at fileURL: URL, paths: [String]) throws {
        let fm = FileManager.default
        let trustDir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: trustDir, withIntermediateDirectories: true)

        var existingLines: [String] = []
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
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

        if changed || !fm.fileExists(atPath: fileURL.path) {
            let output = existingLines.joined(separator: "\n") + "\n"
            try output.write(to: fileURL, atomically: true, encoding: .utf8)
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
