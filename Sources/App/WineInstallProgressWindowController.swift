import Foundation
import AppKit

public final class WineInstallProgressWindowController: NSWindowController {
    public var onCancel: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let cancelButton = NSButton()

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.center()
        super.init(window: window)

        setupUI()
        update(stage: .preparing)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let l10n = LocalizationManager.shared
        window.title = l10n.string(.wineProgressWindowTitle)

        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 440, height: 150))
        window.contentView = contentView

        titleLabel.stringValue = l10n.string(.wineProgressWindowTitle)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear

        statusLabel.stringValue = l10n.string(.wineProgressPreparing)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.backgroundColor = .clear

        progressBar.style = .bar
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)

        cancelButton.title = l10n.string(.alertCancelButton)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(handleCancel)

        let stack = NSStackView(views: [titleLabel, statusLabel, progressBar, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
    }

    public func update(stage: WineInstallStage) {
        let l10n = LocalizationManager.shared
        switch stage {
        case .preparing:
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
            statusLabel.stringValue = l10n.string(.wineProgressPreparing)
        case .downloading(let receivedBytes, let expectedBytes):
            progressBar.isIndeterminate = false
            progressBar.minValue = 0
            progressBar.maxValue = 100
            let receivedMB = Int(receivedBytes / (1024 * 1024))
            let totalMB = Int(max(1, expectedBytes / (1024 * 1024)))
            let pct = expectedBytes > 0 ? Int((Double(receivedBytes) / Double(expectedBytes)) * 100) : 0
            progressBar.doubleValue = Double(pct)
            statusLabel.stringValue = l10n.string(.wineProgressDownloading, receivedMB, totalMB, pct)
        case .extracting:
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
            statusLabel.stringValue = l10n.string(.wineProgressExtracting)
        }
    }

    @objc private func handleCancel() {
        onCancel?()
        self.close()
    }
}
