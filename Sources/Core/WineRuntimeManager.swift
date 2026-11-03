import Foundation

public enum WineInstallStage: Equatable {
    case preparing
    case downloading(receivedBytes: Int64, expectedBytes: Int64)
    case extracting
}

public enum WineRuntimeError: LocalizedError, Equatable {
    case cancelled
    case downloadFailed(String)
    case extractionFailed(String)
    case binaryNotFoundAfterInstall
    case launchFailed(String)

    public var errorDescription: String? {
        let l10n = LocalizationManager.shared
        switch self {
        case .cancelled:
            return l10n.string(.alertCancelButton)
        case .downloadFailed(let msg):
            return l10n.string(.errorWineInstallFailed, msg)
        case .extractionFailed(let msg):
            return l10n.string(.errorWineInstallFailed, msg)
        case .binaryNotFoundAfterInstall:
            return l10n.string(.errorWineInstallFailed, "Wine binary not found after installation.")
        case .launchFailed(let msg):
            return l10n.string(.errorLaunchFailed, msg)
        }
    }
}

public final class WineRuntimeManager: NSObject {
    public static let shared = WineRuntimeManager()
    public static let fallbackDownloadURL = URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-devel-11.21-osx64.tar.xz")!

    public let runtimeRootURL: URL
    public let winePrefixURL: URL
    private let additionalSearchPaths: [URL]

    public init(runtimeRootURL: URL? = nil, winePrefixURL: URL? = nil, additionalSearchPaths: [URL]? = nil) {
        let home = SessionManager.realUserHomeDirectory()
        self.runtimeRootURL = runtimeRootURL ?? home.appendingPathComponent("Library/Application Support/BugOnExe/Runtime", isDirectory: true)
        self.winePrefixURL = winePrefixURL ?? home.appendingPathComponent("Library/Application Support/BugOnExe/WinePrefix", isDirectory: true)

        if let explicit = additionalSearchPaths {
            self.additionalSearchPaths = explicit
        } else {
            self.additionalSearchPaths = [
                URL(fileURLWithPath: "/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine"),
                URL(fileURLWithPath: "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine"),
                URL(fileURLWithPath: "/Applications/Wine Staging.app/Contents/Resources/wine/bin/wine"),
                URL(fileURLWithPath: "/Applications/Wine Crossover.app/Contents/Resources/wine/bin/wine"),
                URL(fileURLWithPath: "/opt/homebrew/bin/wine"),
                URL(fileURLWithPath: "/usr/local/bin/wine"),
                URL(fileURLWithPath: "/opt/homebrew/bin/wine64"),
                URL(fileURLWithPath: "/usr/local/bin/wine64")
            ]
        }
        super.init()
    }

    public func locateWineBinary() -> URL? {
        let fm = FileManager.default

        // 1. Search inside managed Runtime directory
        if fm.fileExists(atPath: runtimeRootURL.path) {
            let candidateAppNames = ["Wine Devel.app", "Wine Stable.app", "Wine Staging.app", "Wine Crossover.app"]
            for appName in candidateAppNames {
                let appURL = runtimeRootURL.appendingPathComponent(appName)
                for relativeBin in ["Contents/Resources/wine/bin/wine", "Contents/Resources/wine/bin/wine64", "Contents/MacOS/wine"] {
                    let binURL = appURL.appendingPathComponent(relativeBin)
                    if fm.isExecutableFile(atPath: binURL.path) {
                        return binURL
                    }
                }
            }

            // General scan inside runtimeRootURL for any .app containing wine executable
            if let items = try? fm.contentsOfDirectory(at: runtimeRootURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for item in items where item.pathExtension.lowercased() == "app" {
                    for relativeBin in ["Contents/Resources/wine/bin/wine", "Contents/Resources/wine/bin/wine64", "Contents/MacOS/wine"] {
                        let binURL = item.appendingPathComponent(relativeBin)
                        if fm.isExecutableFile(atPath: binURL.path) {
                            return binURL
                        }
                    }
                }
            }
        }

        // 2. Search configured additional / system paths
        for path in additionalSearchPaths {
            if fm.isExecutableFile(atPath: path.path) {
                return path
            }
        }

        return nil
    }

    public func extractWineArchive(at archiveURL: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: runtimeRootURL, withIntermediateDirectories: true)

        let tarProc = Process()
        tarProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tarProc.arguments = ["-xf", archiveURL.path, "-C", runtimeRootURL.path]
        do {
            try tarProc.run()
            tarProc.waitUntilExit()
        } catch {
            throw WineRuntimeError.extractionFailed(error.localizedDescription)
        }

        guard tarProc.terminationStatus == 0 else {
            throw WineRuntimeError.extractionFailed("tar exited with status \(tarProc.terminationStatus)")
        }

        let xattrProc = Process()
        xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProc.arguments = ["-cr", runtimeRootURL.path]
        try? xattrProc.run()
        xattrProc.waitUntilExit()

        guard let binURL = locateWineBinary() else {
            throw WineRuntimeError.binaryNotFoundAfterInstall
        }
        return binURL
    }

    public func buildLaunchProcess(exeURL: URL, wineBinaryURL: URL) throws -> Process {
        let fm = FileManager.default
        try fm.createDirectory(at: winePrefixURL, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = wineBinaryURL
        proc.arguments = [exeURL.path]
        proc.currentDirectoryURL = exeURL.deletingLastPathComponent()

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefixURL.path
        env["WINEDEBUG"] = "-all"
        proc.environment = env

        return proc
    }

    public func launchWindowsExecutable(exeURL: URL, wineBinaryURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            let proc = try buildLaunchProcess(exeURL: exeURL, wineBinaryURL: wineBinaryURL)
            try proc.run()
            completion(.success(()))
        } catch {
            completion(.failure(WineRuntimeError.launchFailed(error.localizedDescription)))
        }
    }

    @discardableResult
    public func downloadAndInstallWine(
        from overrideURL: URL? = nil,
        progressHandler: @escaping (WineInstallStage) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> URLSessionDownloadTask? {
        let downloadURL = overrideURL ?? Self.fallbackDownloadURL

        // Handle local file URLs directly (used in unit tests)
        if downloadURL.isFileURL {
            DispatchQueue.global(qos: .userInitiated).async {
                progressHandler(.preparing)
                progressHandler(.extracting)
                do {
                    let bin = try self.extractWineArchive(at: downloadURL)
                    completion(.success(bin))
                } catch {
                    completion(.failure(error))
                }
            }
            return nil
        }

        progressHandler(.preparing)
        let delegate = WineDownloadSessionDelegate(
            progressHandler: progressHandler,
            onSuccess: { [weak self] tempLocation in
                guard let self = self else { return }
                progressHandler(.extracting)
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let bin = try self.extractWineArchive(at: tempLocation)
                        try? FileManager.default.removeItem(at: tempLocation)
                        completion(.success(bin))
                    } catch {
                        try? FileManager.default.removeItem(at: tempLocation)
                        completion(.failure(error))
                    }
                }
            },
            onFailure: { error in
                completion(.failure(WineRuntimeError.downloadFailed(error.localizedDescription)))
            }
        )

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.downloadTask(with: downloadURL)
        task.resume()
        return task
    }
}

private final class WineDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private let progressHandler: (WineInstallStage) -> Void
    private let onSuccess: (URL) -> Void
    private let onFailure: (Error) -> Void

    init(
        progressHandler: @escaping (WineInstallStage) -> Void,
        onSuccess: @escaping (URL) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.progressHandler = progressHandler
        self.onSuccess = onSuccess
        self.onFailure = onFailure
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        DispatchQueue.main.async {
            self.progressHandler(.downloading(receivedBytes: totalBytesWritten, expectedBytes: totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempTarget = FileManager.default.temporaryDirectory.appendingPathComponent("wine-\(UUID().uuidString).tar.xz")
        do {
            try FileManager.default.moveItem(at: location, to: tempTarget)
            onSuccess(tempTarget)
        } catch {
            onFailure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onFailure(error)
        }
    }
}
