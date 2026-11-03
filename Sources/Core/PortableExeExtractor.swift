import Foundation

public enum PortableExtractorError: LocalizedError, Equatable {
    case fileUnreadable(String)
    case notAValidExecutable
    case archiveExtractionFailed(String)
    case innerExecutableNotFound

    public var errorDescription: String? {
        switch self {
        case .fileUnreadable(let msg):
            return "Unable to read file: \(msg)"
        case .notAValidExecutable:
            return "The selected file is not a valid Windows or Flash executable."
        case .archiveExtractionFailed(let msg):
            return "Failed to extract portable archive payload: \(msg)"
        case .innerExecutableNotFound:
            return "Could not find a valid executable inside the portable archive."
        }
    }
}

public enum ExeExecutableKind: Equatable {
    case flash(SwfPayload)
    case sevenZipSfx(archiveOffset: Int, runProgram: String?)
    case standaloneWin32
}

public enum PortableExeExtractor {
    private static let sevenZipMagic = Data([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
    private static let sfxConfigStart = ";!@Install@!UTF-8!".data(using: .utf8)!
    private static let sfxConfigEnd = ";!@InstallEnd@!".data(using: .utf8)!

    public static func classify(fileURL: URL) throws -> ExeExecutableKind {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw PortableExtractorError.fileUnreadable(error.localizedDescription)
        }
        return try classify(data: data)
    }

    public static func classify(data: Data) throws -> ExeExecutableKind {
        let data = data.startIndex == 0 ? data : Data(data)

        // 1. Check for Flash payload first
        if let flashPayload = try? ExeSwfExtractor.extract(from: data) {
            return .flash(flashPayload)
        }

        // 2. Must start with DOS/PE "MZ" header
        guard data.count >= 64, data[0] == 0x4D, data[1] == 0x5A else {
            throw PortableExtractorError.notAValidExecutable
        }

        // 3. Search for 7-Zip archive signature at offset > 0
        if let matchRange = data.range(of: sevenZipMagic, options: [], in: 2..<data.count) {
            let offset = matchRange.lowerBound
            var runProgram: String? = nil

            // Check if there is an SFX config block before the 7z magic
            let prefixSlice = data.subdata(in: 0..<offset)
            if let startRange = prefixSlice.range(of: sfxConfigStart) {
                let searchAfter = startRange.lowerBound..<prefixSlice.count
                if let endRange = prefixSlice.range(of: sfxConfigEnd, options: [], in: searchAfter) {
                    let configSlice = prefixSlice.subdata(in: startRange.lowerBound..<endRange.upperBound)
                    runProgram = parseSfxRunProgram(from: configSlice)
                }
            }

            return .sevenZipSfx(archiveOffset: offset, runProgram: runProgram)
        }

        // 4. Plain Win32 PE executable
        return .standaloneWin32
    }

    public static func parseSfxRunProgram(from configData: Data) -> String? {
        guard let text = String(data: configData, encoding: .utf8) ?? String(data: configData, encoding: .ascii) else {
            return nil
        }

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("runprogram=") else { continue }

            let rawVal = trimmed.dropFirst("runprogram=".count).trimmingCharacters(in: .whitespacesAndNewlines)
            var unquoted = rawVal
            if unquoted.hasPrefix("\"") && unquoted.hasSuffix("\"") && unquoted.count >= 2 {
                unquoted = String(unquoted.dropFirst().dropLast())
            }
            // Replace escaped quotes \" with "
            unquoted = unquoted.replacingOccurrences(of: "\\\"", with: "\"")

            // Extract the executable token (first quoted string or first space-separated token)
            var exeToken: String
            if unquoted.hasPrefix("\"") {
                let afterQuote = unquoted.dropFirst()
                if let closingQuoteIdx = afterQuote.firstIndex(of: "\"") {
                    exeToken = String(afterQuote[..<closingQuoteIdx])
                } else {
                    exeToken = String(afterQuote)
                }
            } else {
                exeToken = unquoted.components(separatedBy: .whitespaces).first ?? unquoted
            }

            exeToken = exeToken.trimmingCharacters(in: .whitespacesAndNewlines)
            // Normalize path separators to forward slash first
            exeToken = exeToken.replacingOccurrences(of: "\\", with: "/")
            while exeToken.contains("//") {
                exeToken = exeToken.replacingOccurrences(of: "//", with: "/")
            }

            // Strip %temp%/ or %%T/ prefix
            if exeToken.lowercased().hasPrefix("%%t/") {
                exeToken = String(exeToken.dropFirst(4))
            } else if exeToken.lowercased().hasPrefix("%temp%/") {
                exeToken = String(exeToken.dropFirst(7))
            }

            while exeToken.hasPrefix("./") || exeToken.hasPrefix("/") {
                exeToken = String(exeToken.dropFirst(exeToken.hasPrefix("./") ? 2 : 1))
            }

            if !exeToken.isEmpty {
                return exeToken
            }
        }
        return nil
    }
}

public final class PortableAppSessionManager {
    public let portableRootURL: URL

    public init(portableRootURL: URL? = nil) {
        self.portableRootURL = portableRootURL ?? SessionManager.realUserHomeDirectory()
            .appendingPathComponent("Library/Application Support/BugOnExe/PortableApps", isDirectory: true)
    }

    public func preparePortableSession(for sourceExeURL: URL, archiveOffset: Int, runProgram: String?) throws -> URL {
        let fm = FileManager.default
        let baseName = sourceExeURL.deletingPathExtension().lastPathComponent
        let pathHash = Self.fnv1aHashHex(sourceExeURL.standardizedFileURL.path)
        let sessionDir = portableRootURL.appendingPathComponent("\(pathHash)-\(baseName)", isDirectory: true)

        let markerURL = sessionDir.appendingPathComponent(".extracted_ok")
        if fm.fileExists(atPath: markerURL.path),
           let relPath = try? String(contentsOf: markerURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !relPath.isEmpty {
            let targetURL = sessionDir.appendingPathComponent(relPath)
            if fm.fileExists(atPath: targetURL.path) {
                cleanKillDuplicateScripts(in: sessionDir)
                return targetURL
            }
        }

        try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        let sourceData: Data
        do {
            sourceData = try Data(contentsOf: sourceExeURL, options: [.mappedIfSafe])
        } catch {
            throw PortableExtractorError.fileUnreadable(error.localizedDescription)
        }

        guard archiveOffset < sourceData.count else {
            throw PortableExtractorError.archiveExtractionFailed("Invalid archive offset")
        }

        let archivePayload = sourceData.subdata(in: archiveOffset..<sourceData.count)
        let tmpArchiveURL = sessionDir.appendingPathComponent(".payload_archive.tmp")
        try archivePayload.write(to: tmpArchiveURL)
        defer { try? fm.removeItem(at: tmpArchiveURL) }

        let tarProc = Process()
        tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProc.arguments = ["-xf", tmpArchiveURL.path, "-C", sessionDir.path]
        do {
            try tarProc.run()
            tarProc.waitUntilExit()
        } catch {
            throw PortableExtractorError.archiveExtractionFailed(error.localizedDescription)
        }

        guard tarProc.terminationStatus == 0 else {
            throw PortableExtractorError.archiveExtractionFailed("tar process exited with status \(tarProc.terminationStatus)")
        }

        cleanKillDuplicateScripts(in: sessionDir)

        let resolvedExecutableURL = try findExecutable(in: sessionDir, preferredRelativePath: runProgram, fallbackBaseName: baseName)

        // Store relative path in .extracted_ok marker
        let relPath = resolvedExecutableURL.path.replacingOccurrences(of: sessionDir.path + "/", with: "")
        try relPath.write(to: markerURL, atomically: true, encoding: .utf8)

        return resolvedExecutableURL
    }

    private func cleanKillDuplicateScripts(in directoryURL: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent.lowercased() == "killduplicate.cmd" {
                try? fm.removeItem(at: fileURL)
            }
        }
    }

    private func findExecutable(in directoryURL: URL, preferredRelativePath: String?, fallbackBaseName: String) throws -> URL {
        let fm = FileManager.default

        // 1. Direct match with preferred path
        if let preferred = preferredRelativePath, !preferred.isEmpty {
            let direct = directoryURL.appendingPathComponent(preferred)
            if fm.fileExists(atPath: direct.path) {
                return direct
            }
            // Case-insensitive file name match across directories
            let targetName = URL(fileURLWithPath: preferred).lastPathComponent.lowercased()
            if let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent.lowercased() == targetName {
                        return fileURL
                    }
                }
            }
        }

        // 2. Scan directory for candidate .exe files (excluding uninstallers/setups)
        var exeCandidates: [URL] = []
        if let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension.lowercased() == "exe" else { continue }
                let lower = fileURL.lastPathComponent.lowercased()
                if lower.hasPrefix("unins") || lower.hasPrefix("setup") || lower == "killduplicate.cmd" {
                    continue
                }
                exeCandidates.append(fileURL)
            }
        }

        guard !exeCandidates.isEmpty else {
            throw PortableExtractorError.innerExecutableNotFound
        }

        // Exact basename match preferred
        let lowerBase = fallbackBaseName.lowercased()
        if let match = exeCandidates.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == lowerBase }) {
            return match
        }

        // Otherwise pick largest executable file
        exeCandidates.sort { (a, b) -> Bool in
            let sizeA = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sizeB = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sizeA > sizeB
        }

        return exeCandidates[0]
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
