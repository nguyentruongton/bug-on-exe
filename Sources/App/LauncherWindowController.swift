import Foundation
import AppKit
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
        onFilesDropped?(items)
        return true
    }
}

public final class LauncherWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let statusLabel = NSTextField(labelWithString: "")
    private let defaultAppButton = NSButton(title: "Đặt làm ứng dụng mặc định mở file .exe", target: nil, action: nil)
    private let tableView = NSTableView()
    private var fileItems: [URL] = []

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bug On Mac exe — Trình chạy Adobe Flash .exe"
        window.center()
        super.init(window: window)
        setupUI()
        reloadFiles()
        refreshDefaultStatus()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let rootView = DropContainerView(frame: window.contentView?.bounds ?? .zero)
        rootView.autoresizingMask = [.width, .height]
        rootView.onFilesDropped = { [weak self] urls in
            for url in urls {
                self?.openAndRun(url: url)
            }
        }
        window.contentView = rootView

        let titleLabel = NSTextField(labelWithString: "Bug On Mac exe")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)

        let subtitleLabel = NSTextField(labelWithString: "Double-click trực tiếp vào file .exe ngoài Finder hoặc kéo-thả / bấm đúp vào danh sách dưới đây để chạy bài thi Flash.")
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

        let colName = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        colName.title = "Tên file (.exe / .swf)"
        colName.width = 300
        tableView.addTableColumn(colName)

        let colPath = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        colPath.title = "Thư mục"
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

        let openButton = NSButton(title: "Mở file .exe khác...", target: self, action: #selector(handleOpenPanel))
        openButton.bezelStyle = .rounded

        let runSelectedButton = NSButton(title: "Chạy bài đã chọn", target: self, action: #selector(handleRunSelected))
        runSelectedButton.bezelStyle = .rounded
        runSelectedButton.keyEquivalent = "\r"

        let refreshButton = NSButton(title: "Làm mới danh sách", target: self, action: #selector(handleRefresh))
        refreshButton.bezelStyle = .rounded

        let bottomBar = NSStackView(views: [openButton, refreshButton, NSView(), runSelectedButton])
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

    public func refreshDefaultStatus() {
        if DefaultAppManager.isDefaultHandlerForExe() {
            statusLabel.stringValue = "✅ Đã là ứng dụng mặc định khi double-click file .exe"
            statusLabel.textColor = .systemGreen
        } else {
            statusLabel.stringValue = "ℹ️ Chưa đặt làm mặc định cho toàn bộ file .exe"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    public func reloadFiles() {
        var combined: [URL] = []
        var seen = Set<String>()

        for recent in ProjectorRunner.recentFiles() {
            let p = recent.standardizedFileURL.path
            if seen.insert(p).inserted {
                combined.append(recent)
            }
        }

        let ic3Root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/IC3")
        for file in DefaultAppManager.discoverExeFiles(in: ic3Root) {
            let p = file.standardizedFileURL.path
            if seen.insert(p).inserted {
                combined.append(file)
            }
        }

        fileItems = combined
        tableView.reloadData()
        if !fileItems.isEmpty && tableView.selectedRow < 0 {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    @objc private func handleSetDefaultApp() {
        let ok = DefaultAppManager.setAsDefaultHandlerForExe()
        refreshDefaultStatus()
        let alert = NSAlert()
        if ok {
            alert.messageText = "Đã đăng ký Bug On Mac exe làm ứng dụng mặc định cho đuôi .exe"
            alert.informativeText = "Từ bây giờ bạn có thể double-click trực tiếp vào các file .exe Flash trong Finder để mở ngay."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Cần xác nhận từ macOS"
            alert.informativeText = "Nếu macOS hỏi xác nhận, hãy chọn 'Use Bug On Mac exe' hoặc chuột phải vào file .exe -> Get Info -> Open with: Bug On Mac exe -> Change All."
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

    @objc private func handleOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Chọn file Adobe Flash .exe hoặc .swf"
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
        ProjectorRunner.run(fileURL: url) { [weak self] result in
            self?.reloadFiles()
            if case .failure(let error) = result {
                let alert = NSAlert()
                alert.messageText = "Không thể mở file \(url.lastPathComponent)"
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
