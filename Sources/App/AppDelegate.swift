import Foundation
import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launcherWindowController: LauncherWindowController?
    private var didOpenFileFromFinder = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self else { return }
            if !self.didOpenFileFromFinder {
                self.showLauncherWindow()
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showLauncherWindow()
        }
        return true
    }

    public func application(_ sender: NSApplication, openFiles filenames: [String]) {
        didOpenFileFromFinder = true
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        handleFinderOpen(urls: urls)
        sender.reply(toOpenOrPrint: .success)
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        didOpenFileFromFinder = true
        handleFinderOpen(urls: urls)
    }

    private func handleFinderOpen(urls: [URL]) {
        let windowVisible = launcherWindowController?.window?.isVisible == true
        let group = DispatchGroup()
        var hadError = false

        for url in urls {
            group.enter()
            ProjectorRunner.run(fileURL: url) { result in
                if case .failure(let error) = result {
                    hadError = true
                    let alert = NSAlert()
                    alert.messageText = "Không thể mở file \(url.lastPathComponent)"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.launcherWindowController?.reloadFiles()
            if !windowVisible && !hadError {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    public func showLauncherWindow() {
        if launcherWindowController == nil {
            launcherWindowController = LauncherWindowController()
        }
        launcherWindowController?.showWindow(nil)
        launcherWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
