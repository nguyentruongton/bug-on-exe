import Foundation
import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

public final class DropContainerView: NSView {
    public var onFilesDropped: (([URL]) -> Void)?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !items.isEmpty else {
            return false
        }
        let validItems = items.filter { ExeLibraryStore.isValidExecutable(url: $0) }
        guard !validItems.isEmpty else {
            let l10n = LocalizationManager.shared
            let alert = NSAlert()
            alert.messageText = l10n.string(.alertUnsupportedTitle)
            alert.informativeText = l10n.string(.alertUnsupportedMessage)
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
        onFilesDropped?(validItems)
        return true
    }
}

public final class LauncherWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static func shouldUseLiquidGlass(majorVersion: Int) -> Bool {
        return majorVersion >= 26
    }

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let defaultAppButton = NSButton(title: "", target: nil, action: nil)
    private let openButton = NSButton(title: "", target: nil, action: nil)
    private let runSelectedButton = NSButton(title: "", target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let languageButton = NSButton(title: "", target: nil, action: nil)
    private let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
    private let colPath = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
    private let tableView = NSTableView()
    private var fileItems: [URL] = []
    private var languageCancellable: AnyCancellable?
    private let useLiquidGlass: Bool

    public var currentFallbackSubtitle: String { subtitleLabel.stringValue }
    public var currentFallbackOpenButtonTitle: String { openButton.title }

    public init(majorVersion: Int? = nil) {
        let currentMajor = majorVersion ?? ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        self.useLiquidGlass = Self.shouldUseLiquidGlass(majorVersion: currentMajor)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 540),
            styleMask: useLiquidGlass
                ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
                : [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)

        if useLiquidGlass {
            window.toolbarStyle = .unified
            setupLiquidGlassUI()
        } else {
            setupFallbackUI()
            reloadFiles()
        }

        applyLocalization()
        languageCancellable = LocalizationManager.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyLocalization()
            }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Liquid Glass UI (macOS >= 26)
    private func setupLiquidGlassUI() {
        let gridView = LauncherCardGridView(
            onOpenFilePicker: { [weak self] in
                self?.handleOpenPanel()
            },
            onRunFile: { [weak self] url in
                self?.openAndRun(url: url)
            }
        )
        let hostingController = NSHostingController(rootView: gridView)
        self.contentViewController = hostingController
    }

    // MARK: - Fallback UI (macOS < 26)
    private func setupFallbackUI() {
        guard let window = self.window else { return }
        let rootView = DropContainerView(frame: window.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        rootView.onFilesDropped = { [weak self] urls in
            for url in urls {
                self?.openAndRun(url: url)
            }
        }
        window.contentView = rootView

        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)

        subtitleLabel.font = NSFont.systemFont(ofSize: 12.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping

        statusLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        defaultAppButton.target = self
        defaultAppButton.action = #selector(handleSetDefaultApp)
        defaultAppButton.bezelStyle = .rounded

        let statusStack = NSStackView(views: [statusLabel, defaultAppButton])
        statusStack.orientation = .horizontal
        statusStack.spacing = 12
        statusStack.alignment = .centerY

        colName.width = 300
        tableView.addTableColumn(colName)

        colPath.width = 320
        tableView.addTableColumn(colPath)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.target = self
        tableView.doubleAction = #selector(handleTableDoubleClick)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        openButton.target = self
        openButton.action = #selector(handleOpenPanel)
        openButton.bezelStyle = .rounded

        runSelectedButton.target = self
        runSelectedButton.action = #selector(handleRunSelected)
        runSelectedButton.bezelStyle = .rounded
        runSelectedButton.keyEquivalent = "\r"

        refreshButton.target = self
        refreshButton.action = #selector(handleRefresh)
        refreshButton.bezelStyle = .rounded

        languageButton.target = self
        languageButton.action = #selector(handleToggleLanguage)
        languageButton.bezelStyle = .rounded

        let bottomBar = NSStackView(views: [openButton, refreshButton, languageButton, NSView(), runSelectedButton])
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 10

        let mainStack = NSStackView(views: [titleLabel, subtitleLabel, statusStack, scrollView, bottomBar])
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            mainStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            mainStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            mainStack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -18),
            scrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            bottomBar.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    public func applyLocalization() {
        let l10n = LocalizationManager.shared
        self.window?.title = l10n.string(.windowTitleManager)

        if !useLiquidGlass {
            titleLabel.stringValue = l10n.string(.fallbackTitle)
            subtitleLabel.stringValue = l10n.string(.windowSubtitleFallback)
            defaultAppButton.title = l10n.string(.statusDefaultFallbackButton)
            colName.title = l10n.string(.fallbackColumnName)
            colPath.title = l10n.string(.fallbackColumnFolder)
            openButton.title = l10n.string(.fallbackOpenButton)
            runSelectedButton.title = l10n.string(.fallbackRunSelectedButton)
            refreshButton.title = l10n.string(.fallbackRefreshButton)
            languageButton.title = "🌐 \(l10n.language.displayName)"
            refreshDefaultStatus()
        }
    }

    public func refreshDefaultStatus() {
        let l10n = LocalizationManager.shared
        if DefaultAppManager.isDefaultHandlerForExe() {
            statusLabel.stringValue = l10n.string(.statusDefaultFallbackActive)
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = l10n.string(.statusDefaultFallbackInactive)
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    public func reloadFiles() {
        var combined: [URL] = []
        var seen = Set<String>()

        for item in ExeLibraryStore.shared.items {
            let p = item.path.standardizedFileURL.path
            if seen.insert(p).inserted {
                combined.append(item.path)
            }
        }

        for recent in ProjectorRunner.recentFiles() {
            let p = recent.standardizedFileURL.path
            if seen.insert(p).inserted {
                combined.append(recent)
            }
        }

        fileItems = combined
        tableView.reloadData()
        if !fileItems.isEmpty && tableView.selectedRow < 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func handleToggleLanguage() {
        LocalizationManager.shared.toggleLanguage()
        applyLocalization()
    }

    @objc private func handleSetDefaultApp() {
        let ok = DefaultAppManager.setAsDefaultHandlerForExe()
        refreshDefaultStatus()
        let l10n = LocalizationManager.shared
        let alert = NSAlert()
        if ok {
            alert.messageText = l10n.string(.alertDefaultSetSuccessTitle)
            alert.informativeText = l10n.string(.alertDefaultSetSuccessMessage)
            alert.alertStyle = .informational
        } else {
            alert.messageText = l10n.string(.alertDefaultSetConfirmTitle)
            alert.informativeText = l10n.string(.alertDefaultSetConfirmMessage)
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    @objc private func handleRefresh() {
        reloadFiles()
        refreshDefaultStatus()
    }

    @objc private func handleTableDoubleClick() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < fileItems.count else { return }
        openAndRun(url: fileItems[row])
    }

    @objc private func handleRunSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < fileItems.count else {
            handleOpenPanel()
            return
        }
        openAndRun(url: fileItems[row])
    }

    @objc public func handleOpenPanel() {
        let l10n = LocalizationManager.shared
        let panel = NSOpenPanel()
        panel.title = l10n.string(.openPanelTitle)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = []
        if let exeType = UTType(filenameExtension: "exe") { types.append(exeType) }
        if let swfType = UTType(filenameExtension: "swf") { types.append(swfType) }
        types.append(.executable)
        panel.allowedContentTypes = types

        if panel.runModal() == .OK, let url = panel.url {
            openAndRun(url: url)
        }
    }

    public func openAndRun(url: URL) {
        ExeLibraryStore.shared.addOrUpdate(url: url)
        ProjectorRunner.run(fileURL: url) { [weak self] result in
            self?.reloadFiles()
            if case .failure(let error) = result {
                let l10n = LocalizationManager.shared
                let alert = NSAlert()
                alert.messageText = l10n.string(.alertOpenErrorTitle, url.lastPathComponent)
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return fileItems.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < fileItems.count else { return nil }
        let item = fileItems[row]
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
        let cell: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField {
            cell = reused
        } else {
            cell = NSTextField(labelWithString: "")
            cell.identifier = id
            cell.lineBreakMode = .byTruncatingMiddle
        }

        if id.rawValue == "name" {
            cell.stringValue = item.lastPathComponent
            cell.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        } else {
            cell.stringValue = item.deletingLastPathComponent().path
            cell.font = NSFont.systemFont(ofSize: 12)
            cell.textColor = .secondaryLabelColor
        }
        return cell
    }
}
