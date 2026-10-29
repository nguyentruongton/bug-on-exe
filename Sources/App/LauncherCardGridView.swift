import SwiftUI
import AppKit
import UniformTypeIdentifiers

public enum SidebarFilter: String, CaseIterable, Identifiable {
    case all
    case pinned
    case recents

    public var id: String { rawValue }
}

public enum CardGridFormatters {
    public static func relativeTimeString(
        from date: Date,
        relativeTo now: Date = Date(),
        language: AppLanguage = LocalizationManager.shared.language
    ) -> String {
        let l10n = LocalizationManager.shared
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return l10n.string(.timeJustNow, language: language)
        } else if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return l10n.string(.timeMinutesAgo, language: language, args: [minutes])
        } else if interval < 86400 {
            let hours = max(1, Int(interval / 3600))
            return l10n.string(.timeHoursAgo, language: language, args: [hours])
        } else if interval < 172800 {
            return l10n.string(.timeYesterday, language: language)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy"
            return formatter.string(from: date)
        }
    }

    public static func filterItems(_ items: [ExeItem], query: String) -> [ExeItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    public static func visibleItems(
        allItems: [ExeItem],
        filter: SidebarFilter,
        query: String
    ) -> (pinned: [ExeItem], recents: [ExeItem]) {
        let matched = filterItems(allItems, query: query)
        let pinned = matched.filter { $0.isPinned }.sorted { $0.lastOpened > $1.lastOpened }
        let recents = Array(matched.filter { !$0.isPinned }.sorted { $0.lastOpened > $1.lastOpened }.prefix(20))

        switch filter {
        case .all:
            return (pinned: pinned, recents: recents)
        case .pinned:
            return (pinned: pinned, recents: [])
        case .recents:
            return (pinned: [], recents: recents)
        }
    }
}

public struct LauncherCardGridView: View {
    @ObservedObject private var store = ExeLibraryStore.shared
    @State private var searchText = ""
    @State private var isDefault = DefaultAppManager.isDefaultHandlerForExe()
    @State private var isWindowDropTargeted = false
    @State private var isDropzoneTargeted = false

    private let onOpenFilePicker: () -> Void
    private let onRunFile: (URL) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 14)
    ]

    public init(
        onOpenFilePicker: @escaping () -> Void,
        onRunFile: @escaping (URL) -> Void
    ) {
        self.onOpenFilePicker = onOpenFilePicker
        self.onRunFile = onRunFile
    }

    public var body: some View {
        ZStack {
            // Liquid Glass Background
            VisualEffectBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topToolbar
                Divider().opacity(0.2)
                mainContent
            }

            // Window Drop Overlay Highlight
            if isWindowDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .ignoresSafeArea()
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
            isDefault = DefaultAppManager.isDefaultHandlerForExe()
        }
        .onDrop(of: [.fileURL], isTargeted: $isWindowDropTargeted) { providers in
            handleDroppedFiles(providers)
            return true
        }
    }

    // MARK: - Top Toolbar
    private var topToolbar: some View {
        HStack(spacing: 12) {
            // Default App Status Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(isDefault ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(isDefault ? "Đã là ứng dụng mặc định .exe" : "Chưa đặt mặc định")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                if !isDefault {
                    Button("Đặt mặc định") {
                        _ = DefaultAppManager.setAsDefaultHandlerForExe()
                        isDefault = DefaultAppManager.isDefaultHandlerForExe()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )

            Spacer()

            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Tìm kiếm file .exe...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 240)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )

            // Add File Button
            Button(action: onOpenFilePicker) {
                Label("Thêm file .exe...", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.leading, 78) // Clear window traffic lights
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - Main Content Area
    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let filteredPinned = CardGridFormatters.filterItems(store.pinnedItems, query: searchText)
                let filteredRecents = CardGridFormatters.filterItems(store.recentItems, query: searchText)

                // 1. Pinned Section
                if !filteredPinned.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("ĐÃ GHIM (PINNED)", systemImage: "star.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                            Spacer()
                        }

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filteredPinned) { item in
                                cardView(item: item)
                            }
                        }
                    }
                }

                // 2. Recents Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("GẦN ĐÂY (RECENTS)", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()

                        if !store.recentItems.isEmpty {
                            Button("Dọn lịch sử") {
                                store.clearRecents()
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredRecents) { item in
                            cardView(item: item)
                        }

                        // Dropzone Add Card
                        dropzoneCard
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Single Card View
    private func cardView(item: ExeItem) -> some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button(action: {
                    store.togglePin(id: item.id)
                }) {
                    Image(systemName: item.isPinned ? "star.fill" : "star")
                        .foregroundColor(item.isPinned ? .orange : .secondary.opacity(0.6))
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
            }

            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: item.isPinned
                                ? [Color.red.opacity(0.85), Color.orange.opacity(0.85)]
                                : [Color.blue.opacity(0.8), Color.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                Text("FL")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }

            VStack(spacing: 3) {
                Text(item.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(item.existsOnDisk ? .primary : .secondary)

                HStack(spacing: 4) {
                    Text(item.fileSizeFormatted)
                    Text("•")
                    Text(CardGridFormatters.relativeTimeString(from: item.lastOpened))
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)

                if !item.existsOnDisk {
                    Text("Không tìm thấy file")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.red)
                }
            }

            // Action Buttons
            HStack(spacing: 6) {
                Button(action: {
                    onRunFile(item.path)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Khởi chạy")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!item.existsOnDisk)

                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([item.path])
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .opacity(item.existsOnDisk ? 1.0 : 0.55) // Dim missing files
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.35), Color.white.opacity(0.08), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 5, x: 0, y: 2)
        )
        .onTapGesture(count: 2) {
            if item.existsOnDisk {
                onRunFile(item.path)
            }
        }
        .contextMenu {
            Button("Khởi chạy") {
                if item.existsOnDisk { onRunFile(item.path) }
            }
            .disabled(!item.existsOnDisk)

            Button("Hiện trong Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.path])
            }

            Button(item.isPinned ? "Bỏ ghim" : "Ghim lên đầu") {
                store.togglePin(id: item.id)
            }

            Divider()

            Button("Xóa khỏi danh sách", role: .destructive) {
                store.remove(id: item.id)
            }
        }
    }

    // MARK: - Dropzone Card
    private var dropzoneCard: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
            }

            Text("Thêm file .exe")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)

            Text("Kéo thả file vào đây\nhoặc click để duyệt")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isDropzoneTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isDropzoneTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenFilePicker()
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropzoneTargeted) { providers in
            handleDroppedFiles(providers)
            return true
        }
    }

    private func handleDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let fileURL = url else { return }
                DispatchQueue.main.async {
                    if ExeLibraryStore.isValidExecutable(url: fileURL) {
                        onRunFile(fileURL)
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "Định dạng không được hỗ trợ"
                        alert.informativeText = "File '\(fileURL.lastPathComponent)' không phải là file thực thi .exe hoặc .swf."
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }
}

// Helper wrapper for AppKit VisualEffect in SwiftUI
public struct VisualEffectBackground: NSViewRepresentable {
    public init() {}
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
