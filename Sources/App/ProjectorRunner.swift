import Foundation
import AppKit

public enum ProjectorRunnerError: LocalizedError, Equatable {
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

public enum ExecutionPlan: Equatable {
    case flash(PreparedSession)
    case windows(exeURL: URL, isExtractedFromSfx: Bool)
}

public final class ProjectorRunner {
    private static let recentFilesKey = "RecentExeFiles"
    private static var activeWineProgressController: WineInstallProgressWindowController?

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

    public static func prepareExecutionPlan(
        fileURL: URL,
        portableSessionManager: PortableAppSessionManager = PortableAppSessionManager()
    ) throws -> ExecutionPlan {
        let kind = try PortableExeExtractor.classify(fileURL: fileURL)
        switch kind {
        case .flash(let payload):
            let session = try SessionManager().prepareSession(for: fileURL, payload: payload)
            recordRecentFile(fileURL)
            return .flash(session)
        case .sevenZipSfx(let archiveOffset, let runProgram):
            let targetExe = try portableSessionManager.preparePortableSession(
                for: fileURL,
                archiveOffset: archiveOffset,
                runProgram: runProgram
            )
            recordRecentFile(fileURL)
            return .windows(exeURL: targetExe, isExtractedFromSfx: true)
        case .standaloneWin32:
            recordRecentFile(fileURL)
            return .windows(exeURL: fileURL, isExtractedFromSfx: false)
        }
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
        DispatchQueue.global(qos: .userInitiated).async {
            let plan: ExecutionPlan
            do {
                plan = try prepareExecutionPlan(fileURL: fileURL)
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            DispatchQueue.main.async {
                switch plan {
                case .flash(let session):
                    launchFlash(session: session, completion: completion)
                case .windows(let targetExeURL, _):
                    launchWindows(sourceFileURL: fileURL, targetExeURL: targetExeURL, completion: completion)
                }
            }
        }
    }

    private static func launchFlash(session: PreparedSession, completion: @escaping (Result<Void, Error>) -> Void) {
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

    private static func launchWindows(
        sourceFileURL: URL,
        targetExeURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let wineMgr = WineRuntimeManager.shared

        if let wineBin = wineMgr.locateWineBinary() {
            wineMgr.launchWindowsExecutable(exeURL: targetExeURL, wineBinaryURL: wineBin, completion: completion)
            return
        }

        // Wine binary is not installed yet: prompt user
        let l10n = LocalizationManager.shared
        let alert = NSAlert()
        alert.messageText = l10n.string(.alertWineRequiredTitle)
        alert.informativeText = l10n.string(.alertWineRequiredMessage, sourceFileURL.lastPathComponent)
        alert.addButton(withTitle: l10n.string(.alertWineInstallButton))
        alert.addButton(withTitle: l10n.string(.alertCancelButton))
        alert.alertStyle = .informational

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            completion(.success(()))
            return
        }

        // Show progress window and start download
        let progressWC = WineInstallProgressWindowController()
        activeWineProgressController = progressWC
        progressWC.showWindow(nil)
        progressWC.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        var downloadTask: URLSessionDownloadTask?
        progressWC.onCancel = {
            downloadTask?.cancel()
            activeWineProgressController = nil
            completion(.success(()))
        }

        downloadTask = wineMgr.downloadAndInstallWine(
            progressHandler: { stage in
                progressWC.update(stage: stage)
            },
            completion: { result in
                progressWC.close()
                activeWineProgressController = nil
                switch result {
                case .success(let installedWineBin):
                    wineMgr.launchWindowsExecutable(exeURL: targetExeURL, wineBinaryURL: installedWineBin, completion: completion)
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
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
