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

    public static func shouldShowEmptySearchState(
        query: String,
        pinned: [ExeItem],
        recents: [ExeItem]
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && pinned.isEmpty && recents.isEmpty
    }
}

public struct LauncherCardGridView: View {
    @ObservedObject private var store = ExeLibraryStore.shared
    @ObservedObject private var l10n = LocalizationManager.shared
    @State private var selectedFilter: SidebarFilter = .all
    @State private var searchText = ""
    @State private var isDefault = DefaultAppManager.isDefaultHandlerForExe()
    @State private var isWindowDropTargeted = false
    @State private var isDropzoneTargeted = false

    private let onOpenFilePicker: () -> Void
    private let onRunFile: (URL) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 215, maximum: 270), spacing: 16)
    ]

    public init(
        onOpenFilePicker: @escaping () -> Void,
        onRunFile: @escaping (URL) -> Void
    ) {
        self.onOpenFilePicker = onOpenFilePicker
        self.onRunFile = onRunFile
    }

    public var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                liquidGlassSplitView
            } else {
                legacyGridLayout
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        .onAppear {
            isDefault = DefaultAppManager.isDefaultHandlerForExe()
        }
        .onDrop(of: [.fileURL], isTargeted: $isWindowDropTargeted) { providers in
            handleDroppedFiles(providers)
            return true
        }
        .overlay {
            if isWindowDropTargeted {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - macOS 26+ Native System App Layout (Liquid Glass)
    @available(macOS 26.0, *)
    private var liquidGlassSplitView: some View {
        NavigationSplitView {
            List(selection: $selectedFilter) {
                Section(l10n.string(.sidebarSectionLibrary)) {
                    NavigationLink(value: SidebarFilter.all) {
                        Label(l10n.string(.sidebarItemAll), systemImage: "square.grid.2x2")
                    }
                    .badge(store.items.count)

                    NavigationLink(value: SidebarFilter.pinned) {
                        Label(l10n.string(.sidebarItemPinned), systemImage: "pin.fill")
                    }
                    .badge(store.pinnedItems.count)

                    NavigationLink(value: SidebarFilter.recents) {
                        Label(l10n.string(.sidebarItemRecents), systemImage: "clock.arrow.circlepath")
                    }
                    .badge(store.recentItems.count)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
            .safeAreaInset(edge: .bottom) {
                liquidGlassDefaultStatusFooter
            }
        } detail: {
            liquidGlassDetailContent
                .navigationTitle(sidebarTitle(for: selectedFilter))
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: Text(l10n.string(.toolbarSearchPlaceholder))
                )
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        languageMenu

                        if !store.recentItems.isEmpty && selectedFilter != .pinned {
                            Button(action: { store.clearRecents() }) {
                                Label(l10n.string(.toolbarClearRecents), systemImage: "trash")
                            }
                            .buttonStyle(.glass)
                            .help(l10n.string(.toolbarClearRecents))
                        }

                        Button(action: onOpenFilePicker) {
                            Label(l10n.string(.toolbarAddFile), systemImage: "plus")
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlassDefaultStatusFooter: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isDefault ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(l10n.string(isDefault ? .statusDefaultActive : .statusDefaultInactive))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if !isDefault {
                    Button(action: {
                        _ = DefaultAppManager.setAsDefaultHandlerForExe()
                        isDefault = DefaultAppManager.isDefaultHandlerForExe()
                    }) {
                        Text(l10n.string(.statusDefaultSetButton))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .padding(10)
    }

    @available(macOS 26.0, *)
    private var liquidGlassDetailContent: some View {
        let slices = CardGridFormatters.visibleItems(
            allItems: store.items,
            filter: selectedFilter,
            query: searchText
        )

        return ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 24) {
                    if selectedFilter != .recents && !slices.pinned.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(l10n.string(.sectionPinned), systemImage: "pin.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.orange)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(slices.pinned) { item in
                                    liquidGlassCard(item: item)
                                }
                            }
                        }
                    }

                    if CardGridFormatters.shouldShowEmptySearchState(
                        query: searchText,
                        pinned: slices.pinned,
                        recents: slices.recents
                    ) {
                        Text(l10n.string(.emptyStateSearch))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .center)
                    } else if selectedFilter == .pinned && slices.pinned.isEmpty {
                        Text(l10n.string(.emptyStatePinned))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                    }

                    if selectedFilter != .pinned {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(l10n.string(.sectionRecents), systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)

                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(slices.recents) { item in
                                    liquidGlassCard(item: item)
                                }

                                liquidGlassDropzoneCard
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    @available(macOS 26.0, *)
    private func liquidGlassCard(item: ExeItem) -> some View {
        let extLabel = item.path.pathExtension.uppercased().isEmpty ? "EXE" : item.path.pathExtension.uppercased()

        return VStack(spacing: 12) {
            HStack {
                Text(extLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .glassEffect(.regular, in: .capsule)

                Spacer()

                Button(action: {
                    store.togglePin(id: item.id)
                }) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.isPinned ? .orange : .secondary)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .help(l10n.string(item.isPinned ? .cardActionUnpin : .cardActionPin))
            }

            // Icon Representation
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: item.isPinned
                                ? [Color.orange.opacity(0.85), Color.red.opacity(0.80)]
                                : [Color.accentColor.opacity(0.85), Color.indigo.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(item.existsOnDisk ? .primary : .secondary)

                HStack(spacing: 4) {
                    Text(item.fileSizeFormatted)
                    Text("•")
                    Text(CardGridFormatters.relativeTimeString(from: item.lastOpened, language: l10n.language))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if !item.existsOnDisk {
                    Text(l10n.string(.cardStatusMissing))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 8) {
                Button(action: {
                    onRunFile(item.path)
                }) {
                    Label(l10n.string(.cardActionRun), systemImage: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .disabled(!item.existsOnDisk)

                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([item.path])
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help(l10n.string(.cardActionRevealInFinder))
            }
        }
        .padding(14)
        .opacity(item.existsOnDisk ? 1.0 : 0.55)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onTapGesture(count: 2) {
            if item.existsOnDisk {
                onRunFile(item.path)
            }
        }
        .contextMenu {
            cardContextMenu(item: item)
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlassDropzoneCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(l10n.string(.dropzoneTitle))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Text(l10n.string(.dropzoneSubtitle))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 165)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDropzoneTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isDropzoneTargeted ? 2 : 1, dash: [6, 4])
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

    // MARK: - Language Switcher Menu
    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button(action: {
                    l10n.language = lang
                }) {
                    HStack {
                        Text(lang.displayName)
                        if l10n.language == lang {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label(l10n.language.shortCode, systemImage: "globe")
        }
        .help(l10n.string(.toolbarLanguage))
    }

    private func sidebarTitle(for filter: SidebarFilter) -> String {
        switch filter {
        case .all: return l10n.string(.sidebarItemAll)
        case .pinned: return l10n.string(.sidebarItemPinned)
        case .recents: return l10n.string(.sidebarItemRecents)
        }
    }

    @ViewBuilder
    private func cardContextMenu(item: ExeItem) -> some View {
        Button(l10n.string(.cardActionRun)) {
            if item.existsOnDisk { onRunFile(item.path) }
        }
        .disabled(!item.existsOnDisk)

        Button(l10n.string(.cardActionRevealInFinder)) {
            NSWorkspace.shared.activateFileViewerSelecting([item.path])
        }

        Button(l10n.string(item.isPinned ? .cardActionUnpin : .cardActionPin)) {
            store.togglePin(id: item.id)
        }

        Divider()

        Button(l10n.string(.cardActionRemove), role: .destructive) {
            store.remove(id: item.id)
        }
    }

    // MARK: - Legacy SwiftUI Layout (macOS < 26 compile-time fallback)
    private var legacyGridLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(l10n.string(isDefault ? .statusDefaultActive : .statusDefaultInactive))
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                languageMenu
                Button(l10n.string(.toolbarAddFile), action: onOpenFilePicker)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(CardGridFormatters.filterItems(store.items, query: searchText)) { item in
                        VStack(spacing: 8) {
                            Text(item.name).font(.headline).lineLimit(1)
                            Button(l10n.string(.cardActionRun)) { onRunFile(item.path) }
                        }
                        .padding(12)
                    }
                }
                .padding(16)
            }
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
                        alert.messageText = l10n.string(.alertUnsupportedTitle)
                        alert.informativeText = l10n.string(.alertUnsupportedMessage)
                        alert.alertStyle = .warning
                        alert.runModal()
                    }
                }
            }
        }
    }
}
