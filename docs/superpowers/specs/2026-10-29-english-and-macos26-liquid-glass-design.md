# English Localization & macOS 26+ Liquid Glass UI Design

## 1. Intent and Why
- **English-first Multi-language Support:** Standardize the application's primary language to **English (`en`)** while supporting **Vietnamese (`vi`)** as the secondary language. Provide an instant language switcher in the toolbar so users can switch between English and Vietnamese on the fly without restarting the app.
- **Authentic macOS 26+ Liquid Glass System App Design:** Replace the custom-drawn flat gray toolbar and `.ultraThinMaterial` approximations with genuine macOS 26 **Liquid Glass** system components and modifiers (`NavigationSplitView`, native floating `.toolbar`, `.searchable`, `GlassEffectContainer`, `.glassEffect(_:in:)`, `.buttonStyle(.glass)`, and `.buttonStyle(.glassProminent)`), matching the official [Apple Liquid Glass documentation](https://developer.apple.com/documentation/technologyoverviews/liquid-glass).

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
1. **Multi-language Architecture (`en` Default, `vi` Secondary):**
   - Set `CFBundleDevelopmentRegion` to `en` and `CFBundleLocalizations` to `["en", "vi"]` in `Resources/Info.plist`.
   - Provide standard bundle string resources (`Resources/en.lproj/Localizable.strings` and `Resources/vi.lproj/Localizable.strings`) packaged into `Bug On Mac exe.app/Contents/Resources/`, backed by an in-memory dictionary fallback so standalone CLI test binaries run identically without requiring a `.app` bundle.
   - Implement `LocalizationManager` (`ObservableObject`) storing the active language (`AppLanguage.english` `"en"` by default, or `.vietnamese` `"vi"`) in `UserDefaults`.
   - Localize 100% of user-facing strings across SwiftUI views, AppKit fallback views, `NSAlert` dialogs, `NSOpenPanel`, relative date/time strings (`CardGridFormatters`), and `ProjectorRunnerError` descriptions.
   - Add a **Language Switcher** control (`EN` / `VI`) directly in the toolbar (both on macOS 26+ Liquid Glass UI and macOS < 26 fallback UI) that updates all visible text immediately.
2. **macOS 26+ System App Architecture & Liquid Glass Components:**
   - Adopt `NavigationSplitView` for the macOS 26+ window:
     - **Floating Liquid Glass Sidebar:** Displays library navigation sections (`All Files`, `Pinned`, `Recents`) with item counts, plus a bottom status card/pill showing the Default `.exe` App Handler status and a one-click `Set as Default` glass button when not yet default.
     - **Detail Content Area & Native Toolbar:** Remove the custom `topToolbar` `HStack`. Use SwiftUI's native `.toolbar` and `.searchable(text: $searchText)` so macOS 26 renders authentic floating Liquid Glass toolbar pills above the scroll view.
     - **Toolbar Controls:** Include the Language Switcher (`English` / `Tiếng Việt`), `Clear Recents` button (when viewing Recents and non-empty), and primary `+ Add .exe File...` button styled with `.buttonStyle(.glassProminent)`.
     - **Liquid Glass Cards & Dropzone:** Use `@available(macOS 26.0, *)` `GlassEffectContainer`, `.glassEffect(.regular, in: .rect(cornerRadius: 16))` / `.capsule`, `.buttonStyle(.glassProminent)` for the primary `Run` button, and `.buttonStyle(.glass)` for secondary card actions (`Reveal in Finder`, `Pin`).
3. **Backward Compatibility (`macOS < 26` Fallback):**
   - Keep deployment target compatibility (`LSMinimumSystemVersion` `13.0`) by gating macOS 26 APIs behind `@available(macOS 26.0, *)` / `#available(macOS 26.0, *)` and preserving the fallback `NSTableView` UI (now fully localized with a language toggle button).

### Non-Goals
- Modifying SWF extraction (`ExeSwfExtractor`) or Flash Player Projector execution (`SessionManager` / `ProjectorRunner` core logic).
- Adding third-party localization dependencies.

### Anti-Goals
- Do not hardcode Vietnamese strings anywhere in UI or error messages.
- Do not require an application restart when toggling between English and Vietnamese.
- Do not stack heavy opaque backgrounds over the content area that block macOS 26 Liquid Glass refraction and depth.

---

## 3. Constraints
- **Compiler & SDK:** Swift 6.3 (`swiftc`), macOS 26.5 SDK available on the build host.
- **Deployment Target:** Compiles cleanly in `scripts/build_app.sh` and all unit test scripts under `Tests/`.
- **Existing Tests:** All 8 existing test suites (`test_extractor.swift`, `test_session.swift`, `test_projector_runner.swift`, `test_default_app.swift`, `test_bundle.swift`, `test_library_store.swift`, `test_fallback_routing.swift`, `test_card_grid_view.swift`) must pass with updated expectations for English default and multi-language formatting.

---

## 4. Approaches Considered

| Approach | Trade-offs | Decision |
| :--- | :--- | :--- |
| **Approach 1: Reactive `LocalizationManager` (`ObservableObject`) + Native macOS 26 `NavigationSplitView` & Liquid Glass APIs** | Instant in-app language switching (`EN` ↔ `VI`) without app restart; guaranteed `en` default regardless of host locale; works in both `.app` bundle and standalone CLI test binaries; authentic macOS 26 system app layout (`NavigationSplitView` + `.toolbar` + `.glassEffect` + `.glass` / `.glassProminent`). | **Selected** |
| **Approach 2: `UserDefaults` `AppleLanguages` Override + App Restart** | Uses standard `Bundle.main` lookup only, but macOS caches bundle language at launch, forcing the user to quit and relaunch the app on language switch; breaks in raw CLI test binaries without a `.app` bundle. | Rejected |

---

## 5. Detailed Design

### 5.1. Localization System (`Sources/Core/LocalizationManager.swift` & `Resources/*.lproj`)
- **`AppLanguage` enum:**
  - Cases: `.english = "en"`, `.vietnamese = "vi"`.
  - Display names: `"English"` (`"EN"`), `"Tiếng Việt"` (`"VI"`).
- **`LocalizationManager` (`ObservableObject`):**
  - Singleton `LocalizationManager.shared`, also instantiable with custom `UserDefaults` for isolated unit tests.
  - `@Published public var language: AppLanguage` persisted under key `"AppLanguage"`, defaulting to `.english` when unset.
  - `public func string(_ key: L10nKey, _ args: CVarArg...) -> String`:
    - Looks up `key.rawValue` in the `.lproj` bundle for `language.rawValue` if present, falling back to the built-in English/Vietnamese table so CLI tests and bundle runs behave identically.
- **Key Localized Strings (`en` / `vi`):**
  - Window titles:
    - `window.title.manager`: `"Bug On Mac exe"` / `"Bug On Mac exe"`
    - `window.subtitle.fallback`: `"Double-click any .exe file in Finder, or drag and drop / double-click an item below to run Flash content."` / `"Double-click trực tiếp vào file .exe ngoài Finder hoặc kéo-thả / bấm đúp vào danh sách dưới đây để chạy bài thi Flash."`
  - Sidebar & Sections:
    - `sidebar.section.library`: `"Library"` / `"Thư viện"`
    - `sidebar.item.all`: `"All Files"` / `"Tất cả file"`
    - `sidebar.item.pinned`: `"Pinned"` / `"Đã ghim"`
    - `sidebar.item.recents`: `"Recents"` / `"Gần đây"`
    - `section.pinned`: `"PINNED"` / `"ĐÃ GHIM"`
    - `section.recents`: `"RECENTS"` / `"GẦN ĐÂY"`
  - Default App Status:
    - `status.default.active`: `"Default for .exe"` / `"Mặc định cho .exe"`
    - `status.default.inactive`: `"Not Default for .exe"` / `"Chưa đặt mặc định .exe"`
    - `status.default.set_button`: `"Set as Default"` / `"Đặt mặc định"`
    - `status.default.fallback_active`: `"✅ Default app for .exe files"` / `"✅ Đã là ứng dụng mặc định khi double-click file .exe"`
    - `status.default.fallback_inactive`: `"ℹ️ Not set as default for .exe files"` / `"ℹ️ Chưa đặt làm mặc định cho toàn bộ file .exe"`
    - `status.default.fallback_button`: `"Set as Default for .exe"` / `"Đặt làm ứng dụng mặc định mở file .exe"`
  - Toolbar & Search:
    - `toolbar.search.placeholder`: `"Search .exe or .swf files..."` / `"Tìm kiếm file .exe hoặc .swf..."`
    - `toolbar.add_file`: `"Add .exe File..."` / `"Thêm file .exe..."`
    - `toolbar.clear_recents`: `"Clear Recents"` / `"Dọn lịch sử"`
    - `toolbar.language`: `"Language"` / `"Ngôn ngữ"`
  - Cards & Dropzone:
    - `card.action.run`: `"Run"` / `"Khởi chạy"`
    - `card.action.reveal_in_finder`: `"Show in Finder"` / `"Hiện trong Finder"`
    - `card.action.pin`: `"Pin"` / `"Ghim lên đầu"`
    - `card.action.unpin`: `"Unpin"` / `"Bỏ ghim"`
    - `card.action.remove`: `"Remove from Library"` / `"Xóa khỏi danh sách"`
    - `card.status.missing`: `"File not found"` / `"Không tìm thấy file"`
    - `dropzone.title`: `"Add .exe File"` / `"Thêm file .exe"`
    - `dropzone.subtitle`: `"Drag and drop a file here\nor click to browse"` / `"Kéo thả file vào đây\nhoặc click để duyệt"`
  - Relative Time (`CardGridFormatters.relativeTimeString(from:relativeTo:language:)`):
    - `time.just_now`: `"Just now"` / `"Vừa mở"`
    - `time.minutes_ago`: `"%d min ago"` / `"%d phút trước"`
    - `time.hours_ago`: `"%d hr ago"` / `"%d giờ trước"`
    - `time.yesterday`: `"Yesterday"` / `"Hôm qua"`
  - Alerts & Errors:
    - `alert.unsupported.title`: `"Unsupported File Format"` / `"Định dạng không được hỗ trợ"`
    - `alert.unsupported.message`: `"Only .exe or .swf files are supported."` / `"Chỉ chấp nhận các tập tin có đuôi .exe hoặc .swf."`
    - `alert.open_error.title`: `"Cannot Open \"%@\""` / `"Không thể mở file \"%@\""`
    - `alert.default_set.success_title`: `"Default App Updated"` / `"Đã đăng ký làm ứng dụng mặc định"`
    - `alert.default_set.success_message`: `"Bug On Mac exe is now the default application for .exe files. You can double-click .exe files in Finder to launch them directly."` / `"Từ bây giờ bạn có thể double-click trực tiếp vào các file .exe Flash trong Finder để mở ngay."`
    - `alert.default_set.confirm_title`: `"macOS Confirmation Required"` / `"Cần xác nhận từ macOS"`
    - `alert.default_set.confirm_message`: `"If prompted by macOS, choose 'Use Bug On Mac exe', or right-click an .exe file in Finder -> Get Info -> Open with -> Change All."` / `"Nếu macOS hỏi xác nhận, hãy chọn 'Use Bug On Mac exe' hoặc chuột phải vào file .exe -> Get Info -> Open with: Bug On Mac exe -> Change All."`
    - `open_panel.title`: `"Choose an Adobe Flash .exe or .swf File"` / `"Chọn file Adobe Flash .exe hoặc .swf"`
    - `error.runtime_missing`: `"Adobe Flash Player Projector runtime was not found inside the application bundle."` / `"Không tìm thấy nhân Adobe Flash Player Projector bên trong gói ứng dụng."`
    - `error.not_flash_exe`: `"This .exe file does not contain an embedded Adobe Flash Projector payload."` / `"File .exe này không chứa nội dung Adobe Flash Projector."`
    - `error.file_unreadable`: `"Unable to read file: %@"` / `"Không thể đọc file: %@"`
    - `error.session_failed`: `"Failed to prepare temporary session: %@"` / `"Không thể khởi tạo phiên chạy tạm: %@"`
    - `error.launch_failed`: `"Failed to launch Flash Player Projector: %@"` / `"Không thể khởi chạy Flash Player Projector: %@"`

### 5.2. macOS 26+ Liquid Glass UI (`Sources/App/LauncherCardGridView.swift` & `LauncherWindowController.swift`)
- **Window Configuration (`LauncherWindowController.swift`):**
  - On `macOS >= 26`:
    - `styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`
    - `toolbarStyle = .unified`
    - `titlebarAppearsTransparent = false` (let `NavigationSplitView` and native macOS 26 toolbar manage the Liquid Glass titlebar/toolbar layer cleanly).
- **System Layout (`LauncherCardGridView.swift` for `@available(macOS 26.0, *)`):**
  - **`NavigationSplitView`:**
    - **Sidebar (`navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)`):**
      - `List(selection: $selectedFilter)` with `SidebarFilter` cases: `.all`, `.pinned`, `.recents`.
      - Each row uses `Label` with SF Symbols (`square.grid.2x2`, `pin.fill`, `clock.arrow.circlepath`) and badge count.
      - `.safeAreaInset(edge: .bottom)` in the sidebar hosts the **Default `.exe` Handler Status** inside a `GlassEffectContainer`:
        - Status dot (`green` or `orange`) + localized status label + `"Set as Default"` button styled with `.buttonStyle(.glass)` and `.controlSize(.small)`, wrapped in `.glassEffect(.regular, in: .rect(cornerRadius: 12))`.
    - **Detail View:**
      - `ScrollView` displaying:
        - When `.all` is selected: **Pinned** section (if any) followed by **Recents** section and the **Add `.exe` Dropzone Card**.
        - When `.pinned` is selected: **Pinned** cards (or empty state).
        - When `.recents` is selected: **Recents** cards + **Add `.exe` Dropzone Card**.
      - **Card Component (`ExeCardView`):**
        - Uses `GlassEffectContainer` and `.glassEffect(.regular, in: .rect(cornerRadius: 16))` for authentic macOS 26 optical refraction and edge specular highlight.
        - Top row: File type badge (`EXE` / `SWF`) and Pin toggle button (`pin.fill` / `pin`) with `.buttonStyle(.glass)` and `.buttonBorderShape(.circle)`.
        - Center: App icon representation (`NSWorkspace.shared.icon(forFile:)` if file exists, or stylized symbol badge) + file name + size & relative timestamp.
        - Bottom action bar: Primary `Run` button (`play.fill`) with `.buttonStyle(.glassProminent)` and `Show in Finder` button (`folder`) with `.buttonStyle(.glass)`.
      - **Native `.searchable` & `.toolbar`:**
        - `.searchable(text: $searchText, placement: .toolbar, prompt: Text(l10n.string(.toolbarSearchPlaceholder)))`
        - `ToolbarItemGroup(placement: .primaryAction)`:
          - Language Switcher `Menu` or `Picker` with globe icon (`globe`) showing current language code (`EN` / `VI`) and options `English` / `Tiếng Việt`.
          - `Clear Recents` button (`trash`) when recents exist.
          - `Add .exe File...` button (`plus`) with `.buttonStyle(.glassProminent)`.

### 5.3. What's Left to the Builder
- Exact spacing, padding, and animation curves on card hover.
- Internal helper structure for `L10nKey` enum and `Localizable.strings` generation in `build_app.sh`.
