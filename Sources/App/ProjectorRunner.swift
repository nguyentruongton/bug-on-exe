import Foundation
import AppKit

public enum ProjectorRunnerError: LocalizedError {
    case projectorRuntimeMissing
    case extractionFailed(ExtractorError)
    case sessionFailed(String)
    case launchFailed(String)

    public var errorDescription: String? {
        let l10n = LocalizationManager.shared
        switch self {
        case .projectorRuntimeMissing:
            return l10n.string(.errorRuntimeMissing)
        case .extractionFailed(let err):
            switch err {
            case .notAFlashExecutable:
                return l10n.string(.errorNotFlashExe)
            case .fileUnreadable(let msg):
                return l10n.string(.errorFileUnreadable, msg)
            }
        case .sessionFailed(let msg):
            return l10n.string(.errorSessionFailed, msg)
        case .launchFailed(let msg):
            return l10n.string(.errorLaunchFailed, msg)
        }
    }
}

public final class ProjectorRunner {
    private static let recentFilesKey = "RecentExeFiles"

    public static func prepareForLaunch(fileURL: URL) throws -> PreparedSession {
        let payload: SwfPayload
        do {
            payload = try ExeSwfExtractor.extract(from: fileURL)
        } catch let err as ExtractorError {
            throw ProjectorRunnerError.extractionFailed(err)
        } catch {
            throw ProjectorRunnerError.sessionFailed(error.localizedDescription)
        }

        let session: PreparedSession
        do {
            session = try SessionManager().prepareSession(for: fileURL, payload: payload)
        } catch {
            throw ProjectorRunnerError.sessionFailed(error.localizedDescription)
        }

        recordRecentFile(fileURL)
        return session
    }

    public static func locateProjectorApp() -> URL? {
        let fm = FileManager.default
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Flash Player.app"),
           fm.fileExists(atPath: bundled.path) {
            return bundled
        }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let relativeBundled = execDir
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Flash Player.app")
        if fm.fileExists(atPath: relativeBundled.path) {
            return relativeBundled
        }
        let systemCopy = URL(fileURLWithPath: "/Applications/Bug On EXE.app/Contents/Resources/Flash Player.app")
        if fm.fileExists(atPath: systemCopy.path) {
            return systemCopy
        }
        let standalone = URL(fileURLWithPath: "/Applications/Flash Player.app")
        if fm.fileExists(atPath: standalone.path) {
            return standalone
        }
        return nil
    }

    public static func run(fileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let session: PreparedSession
        do {
            session = try prepareForLaunch(fileURL: fileURL)
        } catch {
            completion(.failure(error))
            return
        }

        guard let projectorURL = locateProjectorApp() else {
            completion(.failure(ProjectorRunnerError.projectorRuntimeMissing))
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true

        NSWorkspace.shared.open(
            [session.swfFileURL],
            withApplicationAt: projectorURL,
            configuration: config
        ) { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(ProjectorRunnerError.launchFailed(error.localizedDescription)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    public static func recordRecentFile(_ url: URL) {
        let path = url.standardizedFileURL.path
        var current = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        current.removeAll { $0 == path }
        current.insert(path, at: 0)
        if current.count > 20 {
            current = Array(current.prefix(20))
        }
        UserDefaults.standard.set(current, forKey: recentFilesKey)
    }

    public static func recentFiles() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: recentFilesKey) ?? []
        return paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
