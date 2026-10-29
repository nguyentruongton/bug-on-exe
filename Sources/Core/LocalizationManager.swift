import Foundation
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case vietnamese = "vi"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }

    public var shortCode: String {
        switch self {
        case .english: return "EN"
        case .vietnamese: return "VI"
        }
    }
}

public enum L10nKey: String, CaseIterable {
    case windowTitleManager = "window.title.manager"
    case windowSubtitleFallback = "window.subtitle.fallback"
    case sidebarSectionLibrary = "sidebar.section.library"
    case sidebarItemAll = "sidebar.item.all"
    case sidebarItemPinned = "sidebar.item.pinned"
    case sidebarItemRecents = "sidebar.item.recents"
    case sectionPinned = "section.pinned"
    case sectionRecents = "section.recents"
    case statusDefaultActive = "status.default.active"
    case statusDefaultInactive = "status.default.inactive"
    case statusDefaultSetButton = "status.default.set_button"
    case statusDefaultFallbackActive = "status.default.fallback_active"
    case statusDefaultFallbackInactive = "status.default.fallback_inactive"
    case statusDefaultFallbackButton = "status.default.fallback_button"
    case toolbarSearchPlaceholder = "toolbar.search.placeholder"
    case toolbarAddFile = "toolbar.add_file"
    case toolbarClearRecents = "toolbar.clear_recents"
    case toolbarLanguage = "toolbar.language"
    case cardActionRun = "card.action.run"
    case cardActionRevealInFinder = "card.action.reveal_in_finder"
    case cardActionPin = "card.action.pin"
    case cardActionUnpin = "card.action.unpin"
    case cardActionRemove = "card.action.remove"
    case cardStatusMissing = "card.status.missing"
    case dropzoneTitle = "dropzone.title"
    case dropzoneSubtitle = "dropzone.subtitle"
    case timeJustNow = "time.just_now"
    case timeMinutesAgo = "time.minutes_ago"
    case timeHoursAgo = "time.hours_ago"
    case timeYesterday = "time.yesterday"
    case alertUnsupportedTitle = "alert.unsupported.title"
    case alertUnsupportedMessage = "alert.unsupported.message"
    case alertOpenErrorTitle = "alert.open_error.title"
    case alertDefaultSetSuccessTitle = "alert.default_set.success_title"
    case alertDefaultSetSuccessMessage = "alert.default_set.success_message"
    case alertDefaultSetConfirmTitle = "alert.default_set.confirm_title"
    case alertDefaultSetConfirmMessage = "alert.default_set.confirm_message"
    case openPanelTitle = "open_panel.title"
    case errorRuntimeMissing = "error.runtime_missing"
    case errorNotFlashExe = "error.not_flash_exe"
    case errorFileUnreadable = "error.file_unreadable"
    case errorSessionFailed = "error.session_failed"
    case errorLaunchFailed = "error.launch_failed"
    case fallbackTitle = "fallback.title"
    case fallbackColumnName = "fallback.column.name"
    case fallbackColumnFolder = "fallback.column.folder"
    case fallbackOpenButton = "fallback.button.open"
    case fallbackRunSelectedButton = "fallback.button.run_selected"
    case fallbackRefreshButton = "fallback.button.refresh"
    case emptyStatePinned = "empty.pinned"
    case emptyStateSearch = "empty.search"
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    private static let storageKey = "AppLanguage"

    private let defaults: UserDefaults
    private let bundle: Bundle

    @Published public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    public init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
        if let saved = defaults.string(forKey: Self.storageKey),
           let parsed = AppLanguage(rawValue: saved) {
            self.language = parsed
        } else {
            self.language = .english
            defaults.set(AppLanguage.english.rawValue, forKey: Self.storageKey)
        }
    }

    public func toggleLanguage() {
        language = (language == .english) ? .vietnamese : .english
    }

    public func string(_ key: L10nKey, _ args: CVarArg...) -> String {
        return string(key, language: self.language, args: args)
    }

    public func string(_ key: L10nKey, language: AppLanguage, args: [CVarArg] = []) -> String {
        let template = resolveTemplate(for: key, language: language)
        guard !args.isEmpty else { return template }
        let locale = Locale(identifier: language.rawValue)
        return String(format: template, locale: locale, arguments: args)
    }

    private func resolveTemplate(for key: L10nKey, language: AppLanguage) -> String {
        if let lprojPath = bundle.path(forResource: language.rawValue, ofType: "lproj"),
           let langBundle = Bundle(path: lprojPath) {
            let localized = langBundle.localizedString(forKey: key.rawValue, value: nil, table: "Localizable")
            if localized != key.rawValue {
                return localized
            }
        }
        if language == .vietnamese, let viVal = Self.vietnameseTable[key] {
            return viVal
        }
        return Self.englishTable[key] ?? key.rawValue
    }

    private static let englishTable: [L10nKey: String] = [
        .windowTitleManager: "Bug On Mac exe",
        .windowSubtitleFallback: "Double-click any .exe file in Finder, or drag and drop / double-click an item below to run Flash content.",
        .sidebarSectionLibrary: "Library",
        .sidebarItemAll: "All Files",
        .sidebarItemPinned: "Pinned",
        .sidebarItemRecents: "Recents",
        .sectionPinned: "PINNED",
        .sectionRecents: "RECENTS",
        .statusDefaultActive: "Default for .exe",
        .statusDefaultInactive: "Not Default for .exe",
        .statusDefaultSetButton: "Set as Default",
        .statusDefaultFallbackActive: "✅ Default app for .exe files",
        .statusDefaultFallbackInactive: "ℹ️ Not set as default for .exe files",
        .statusDefaultFallbackButton: "Set as Default for .exe",
        .toolbarSearchPlaceholder: "Search .exe or .swf files...",
        .toolbarAddFile: "Add .exe File...",
        .toolbarClearRecents: "Clear Recents",
        .toolbarLanguage: "Language",
        .cardActionRun: "Run",
        .cardActionRevealInFinder: "Show in Finder",
        .cardActionPin: "Pin",
        .cardActionUnpin: "Unpin",
        .cardActionRemove: "Remove from Library",
        .cardStatusMissing: "File not found",
        .dropzoneTitle: "Add .exe File",
        .dropzoneSubtitle: "Drag and drop a file here\nor click to browse",
        .timeJustNow: "Just now",
        .timeMinutesAgo: "%d min ago",
        .timeHoursAgo: "%d hr ago",
        .timeYesterday: "Yesterday",
        .alertUnsupportedTitle: "Unsupported File Format",
        .alertUnsupportedMessage: "Only .exe or .swf files are supported.",
        .alertOpenErrorTitle: "Cannot Open \"%@\"",
        .alertDefaultSetSuccessTitle: "Default App Updated",
        .alertDefaultSetSuccessMessage: "Bug On Mac exe is now the default application for .exe files. You can double-click .exe files in Finder to launch them directly.",
        .alertDefaultSetConfirmTitle: "macOS Confirmation Required",
        .alertDefaultSetConfirmMessage: "If prompted by macOS, choose 'Use Bug On Mac exe', or right-click an .exe file in Finder -> Get Info -> Open with -> Change All.",
        .openPanelTitle: "Choose an Adobe Flash .exe or .swf File",
        .errorRuntimeMissing: "Adobe Flash Player Projector runtime was not found inside the application bundle.",
        .errorNotFlashExe: "This .exe file does not contain an embedded Adobe Flash Projector payload.",
        .errorFileUnreadable: "Unable to read file: %@",
        .errorSessionFailed: "Failed to prepare temporary session: %@",
        .errorLaunchFailed: "Failed to launch Flash Player Projector: %@",
        .fallbackTitle: "Bug On Mac exe",
        .fallbackColumnName: "File Name (.exe / .swf)",
        .fallbackColumnFolder: "Folder",
        .fallbackOpenButton: "Open Another .exe File...",
        .fallbackRunSelectedButton: "Run Selected",
        .fallbackRefreshButton: "Refresh List",
        .emptyStatePinned: "No pinned files yet. Click the pin icon on any card to keep it at the top.",
        .emptyStateSearch: "No matching .exe or .swf files found."
    ]

    private static let vietnameseTable: [L10nKey: String] = [
        .windowTitleManager: "Bug On Mac exe",
        .windowSubtitleFallback: "Double-click trực tiếp vào file .exe ngoài Finder hoặc kéo-thả / bấm đúp vào danh sách dưới đây để chạy bài thi Flash.",
        .sidebarSectionLibrary: "Thư viện",
        .sidebarItemAll: "Tất cả file",
        .sidebarItemPinned: "Đã ghim",
        .sidebarItemRecents: "Gần đây",
        .sectionPinned: "ĐÃ GHIM",
        .sectionRecents: "GẦN ĐÂY",
        .statusDefaultActive: "Mặc định cho .exe",
        .statusDefaultInactive: "Chưa đặt mặc định .exe",
        .statusDefaultSetButton: "Đặt mặc định",
        .statusDefaultFallbackActive: "✅ Đã là ứng dụng mặc định khi double-click file .exe",
        .statusDefaultFallbackInactive: "ℹ️ Chưa đặt làm mặc định cho toàn bộ file .exe",
        .statusDefaultFallbackButton: "Đặt làm ứng dụng mặc định mở file .exe",
        .toolbarSearchPlaceholder: "Tìm kiếm file .exe hoặc .swf...",
        .toolbarAddFile: "Thêm file .exe...",
        .toolbarClearRecents: "Dọn lịch sử",
        .toolbarLanguage: "Ngôn ngữ",
        .cardActionRun: "Khởi chạy",
        .cardActionRevealInFinder: "Hiện trong Finder",
        .cardActionPin: "Ghim lên đầu",
        .cardActionUnpin: "Bỏ ghim",
        .cardActionRemove: "Xóa khỏi danh sách",
        .cardStatusMissing: "Không tìm thấy file",
        .dropzoneTitle: "Thêm file .exe",
        .dropzoneSubtitle: "Kéo thả file vào đây\nhoặc click để duyệt",
        .timeJustNow: "Vừa mở",
        .timeMinutesAgo: "%d phút trước",
        .timeHoursAgo: "%d giờ trước",
        .timeYesterday: "Hôm qua",
        .alertUnsupportedTitle: "Định dạng không được hỗ trợ",
        .alertUnsupportedMessage: "Chỉ chấp nhận các tập tin có đuôi .exe hoặc .swf.",
        .alertOpenErrorTitle: "Không thể mở file \"%@\"",
        .alertDefaultSetSuccessTitle: "Đã đăng ký làm ứng dụng mặc định",
        .alertDefaultSetSuccessMessage: "Từ bây giờ bạn có thể double-click trực tiếp vào các file .exe Flash trong Finder để mở ngay.",
        .alertDefaultSetConfirmTitle: "Cần xác nhận từ macOS",
        .alertDefaultSetConfirmMessage: "Nếu macOS hỏi xác nhận, hãy chọn 'Use Bug On Mac exe' hoặc chuột phải vào file .exe -> Get Info -> Open with: Bug On Mac exe -> Change All.",
        .openPanelTitle: "Chọn file Adobe Flash .exe hoặc .swf",
        .errorRuntimeMissing: "Không tìm thấy nhân Adobe Flash Player Projector bên trong gói ứng dụng.",
        .errorNotFlashExe: "File .exe này không chứa nội dung Adobe Flash Projector.",
        .errorFileUnreadable: "Không thể đọc file: %@",
        .errorSessionFailed: "Không thể khởi tạo phiên chạy tạm: %@",
        .errorLaunchFailed: "Không thể khởi chạy Flash Player Projector: %@",
        .fallbackTitle: "Bug On Mac exe",
        .fallbackColumnName: "Tên file (.exe / .swf)",
        .fallbackColumnFolder: "Thư mục",
        .fallbackOpenButton: "Mở file .exe khác...",
        .fallbackRunSelectedButton: "Chạy bài đã chọn",
        .fallbackRefreshButton: "Làm mới danh sách",
        .emptyStatePinned: "Chưa có file nào được ghim. Hãy bấm biểu tượng ghim trên thẻ để giữ file ở đầu danh sách.",
        .emptyStateSearch: "Không tìm thấy file .exe hoặc .swf phù hợp."
    ]
}
