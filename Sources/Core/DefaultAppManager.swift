import Foundation
import CoreServices
import UniformTypeIdentifiers
import AppKit

public enum DefaultAppManager {
    public static let bundleIdentifier = "com.stark.bugonmacexe"

    public static var exeUTIs: [String] {
        var list = [
            "com.microsoft.windows-executable",
            "public.executable",
            "com.stark.bugonmacexe.exe"
        ]
        if let preferred = UTType(filenameExtension: "exe")?.identifier {
            if !list.contains(preferred) {
                list.insert(preferred, at: 0)
            }
        }
        return list
    }

    public static func matchesBundleIdentifier(
        _ targetBundleID: String,
        primaryHandler: String?,
        fallbackHandlers: [String]
    ) -> Bool {
        if let primary = primaryHandler, !primary.isEmpty {
            return primary.caseInsensitiveCompare(targetBundleID) == .orderedSame
        }
        for handler in fallbackHandlers where !handler.isEmpty {
            if handler.caseInsensitiveCompare(targetBundleID) == .orderedSame {
                return true
            }
        }
        return false
    }

    public static func isDefaultHandlerForExe() -> Bool {
        let utis = exeUTIs
        let primaryUTI = utis.first ?? "com.microsoft.windows-executable"
        let primaryHandler = LSCopyDefaultRoleHandlerForContentType(primaryUTI as CFString, .all)?.takeRetainedValue() as String?
        let fallbacks = utis.dropFirst().compactMap {
            LSCopyDefaultRoleHandlerForContentType($0 as CFString, .all)?.takeRetainedValue() as String?
        }
        return matchesBundleIdentifier(bundleIdentifier, primaryHandler: primaryHandler, fallbackHandlers: fallbacks)
    }

    @discardableResult
    public static func setAsDefaultHandlerForExe() -> Bool {
        var success = false
        for uti in exeUTIs {
            let status = LSSetDefaultRoleHandlerForContentType(
                uti as CFString,
                .all,
                bundleIdentifier as CFString
            )
            if status == noErr {
                success = true
            }
        }
        _ = LSSetDefaultRoleHandlerForContentType(
            "com.macromedia.shockwave-flash" as CFString,
            .all,
            bundleIdentifier as CFString
        )
        return success
    }

    public static func discoverExeFiles(in rootDirectory: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: rootDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var found: [URL] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "exe" || ext == "swf" {
                found.append(fileURL)
            }
        }

        return found.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
