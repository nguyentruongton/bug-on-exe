# English Localization & macOS 26+ Liquid Glass UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Standardize the application's primary language to English (`en`) with Vietnamese (`vi`) as a secondary language switched instantly from the toolbar, and upgrade the macOS 26+ interface to an authentic system-style `NavigationSplitView` with Apple's native Liquid Glass components and modifiers.

**Architecture:** Introduce a reactive `LocalizationManager` (`ObservableObject`) backed by `Resources/en.lproj/Localizable.strings`, `Resources/vi.lproj/Localizable.strings`, and an in-memory fallback table for standalone test binaries. Refactor `LauncherCardGridView` on `@available(macOS 26.0, *)` to use `NavigationSplitView`, native floating `.toolbar` + `.searchable`, `GlassEffectContainer`, `.glassEffect(_:in:)`, `.buttonStyle(.glass)`, and `.buttonStyle(.glassProminent)`, while localizing `ProjectorRunner`, `AppDelegate`, and the `macOS < 26` fallback `LauncherWindowController`.

**Tech Stack:** Swift 6.3 (`swiftc`), SwiftUI (`NavigationSplitView`, `GlassEffectContainer`, `.glassEffect`, `.glass`, `.glassProminent`), AppKit (`NSWindow`, `NSHostingController`, `NSTableView`).

**Spec:** `docs/superpowers/specs/2026-10-29-english-and-macos26-liquid-glass-design.md`

## Global Constraints

- `CFBundleDevelopmentRegion` must be `en` and `CFBundleLocalizations` must be `["en", "vi"]` in `Resources/Info.plist`.
- Default language on a fresh install or unset `UserDefaults` key `"AppLanguage"` must always be `.english` (`"en"`), regardless of the host macOS locale.
- Toggling language between English (`en`) and Vietnamese (`vi`) must update all visible UI strings immediately without restarting the app.
- macOS 26+ APIs (`GlassEffectContainer`, `.glassEffect`, `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`) must be gated with `@available(macOS 26.0, *)` / `#available(macOS 26.0, *)` so `LSMinimumSystemVersion` `13.0` remains valid.
- All CLI test suites compiled via `swiftc` must pass without requiring a mounted `.app` bundle at test time (except `test_bundle.swift` which explicitly verifies `/Applications/Bug On Mac exe.app`).

## Review Focus

- Unset or corrupted `"AppLanguage"` value in `UserDefaults` must gracefully fall back to `.english` (`"en"`).
- Format strings with arguments (e.g., `alert.open_error.title`, `time.minutes_ago`, `error.file_unreadable`) must substitute `%@` and `%d` accurately in both `en` and `vi`.
- Sidebar filter selection (`.all`, `.pinned`, `.recents`) combined with a non-empty search query must filter only within the selected category without mutating `ExeLibraryStore`.
- Switching language in `LauncherWindowController` fallback mode (`macOS < 26`) must immediately update window title, subtitle, table column headers, status label, and buttons.
- `scripts/build_app.sh` must copy `en.lproj` and `vi.lproj` into `Bug On Mac exe.app/Contents/Resources/` and compile `LocalizationManager.swift` in the binary target.

---

### Task 1: Multi-Language Engine (`LocalizationManager`) & Bundle String Resources

**Files:**
- Create: `Sources/Core/LocalizationManager.swift`
- Create: `Resources/en.lproj/Localizable.strings`
- Create: `Resources/vi.lproj/Localizable.strings`
- Modify: `Resources/Info.plist:5-7`
- Create: `Tests/test_localization.swift`

**Interfaces:**
- Consumes: `Foundation`, `Combine`
- Produces:
  - `public enum AppLanguage: String, CaseIterable, Identifiable` (`.english = "en"`, `.vietnamese = "vi"`, `public var displayName: String`, `public var shortCode: String`)
  - `public enum L10nKey: String, CaseIterable` (all keys defined in spec section 5.1, plus fallback table headers/buttons: `fallbackTitle`, `fallbackColumnName`, `fallbackColumnFolder`, `fallbackOpenButton`, `fallbackRunSelectedButton`, `fallbackRefreshButton`, `emptyStatePinned`, `emptyStateSearch`)
  - `public final class LocalizationManager: ObservableObject`
    - `public static let shared: LocalizationManager`
    - `@Published public var language: AppLanguage`
    - `public init(defaults: UserDefaults = .standard, bundle: Bundle = .main)`
    - `public func toggleLanguage()`
    - `public func string(_ key: L10nKey, _ args: CVarArg...) -> String`

- [ ] **Step 1: Write the failing localization test (`Tests/test_localization.swift`)**

```swift
import Foundation

@main
struct LocalizationTestRunner {
    static func main() throws {
        let suiteName = "test.localization.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. Default language is English even when unset or invalid
        let manager = LocalizationManager(defaults: defaults)
        assert(manager.language == .english, "Default language must be English")
        assert(manager.string(.toolbarAddFile) == "Add .exe File...")
        assert(manager.string(.sidebarItemAll) == "All Files")
        assert(manager.string(.timeMinutesAgo, 5) == "5 min ago")
        assert(manager.string(.alertOpenErrorTitle, "demo.exe") == "Cannot Open \"demo.exe\"")

        // 2. Corrupted UserDefaults value falls back to English
        defaults.set("fr_INVALID", forKey: "AppLanguage")
        let fallbackManager = LocalizationManager(defaults: defaults)
        assert(fallbackManager.language == .english, "Corrupted language key must fallback to English")

        // 3. Switch to Vietnamese updates strings and persists to UserDefaults
        manager.language = .vietnamese
        assert(defaults.string(forKey: "AppLanguage") == "vi")
        assert(manager.string(.toolbarAddFile) == "Thêm file .exe...")
        assert(manager.string(.sidebarItemAll) == "Tất cả file")
        assert(manager.string(.timeMinutesAgo, 5) == "5 phút trước")
        assert(manager.string(.alertOpenErrorTitle, "demo.exe") == "Không thể mở file \"demo.exe\"")

        // 4. Toggle helper cycles English <-> Vietnamese
        manager.toggleLanguage()
        assert(manager.language == .english)
        manager.toggleLanguage()
        assert(manager.language == .vietnamese)

        // 5. Every L10nKey has non-empty translations in both languages
        for lang in AppLanguage.allCases {
            manager.language = lang
            for key in L10nKey.allCases {
                let val = manager.string(key)
                assert(!val.isEmpty && val != key.rawValue, "Missing translation for \(key.rawValue) in \(lang.rawValue)")
            }
        }

        print("ALL LOCALIZATION TESTS PASSED")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -target x86_64-apple-macosx13.0 Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization && /tmp/test_localization`
Expected: FAIL (`no such file or directory: 'Sources/Core/LocalizationManager.swift'`)

- [ ] **Step 3: Create `Resources/en.lproj/Localizable.strings`, `Resources/vi.lproj/Localizable.strings`, update `Resources/Info.plist`, and implement `Sources/Core/LocalizationManager.swift`**

In `Resources/Info.plist`, change `<key>CFBundleDevelopmentRegion</key><string>vi</string>` to `<string>en</string>` and add:
```xml
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>vi</string>
    </array>
```

In `Sources/Core/LocalizationManager.swift`, define `AppLanguage`, `L10nKey`, and `LocalizationManager` with bundle `.lproj` lookup (`bundle.path(forResource: language.rawValue, ofType: "lproj")`) and an in-memory dictionary fallback for all `L10nKey` cases in both `.english` and `.vietnamese`, formatting variadic `CVarArg` via `String(format: locale: arguments:)`.

- [ ] **Step 4: Run the localization test to verify it passes**

Run: `swiftc -target x86_64-apple-macosx13.0 Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization && /tmp/test_localization`
Expected: PASS (`ALL LOCALIZATION TESTS PASSED`)

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/Core/LocalizationManager.swift Resources/en.lproj/Localizable.strings Resources/vi.lproj/Localizable.strings Resources/Info.plist Tests/test_localization.swift
git commit -m "feat(l10n): add LocalizationManager with English default and Vietnamese support"
```

---

### Task 2: Localize `ProjectorRunnerError` and `CardGridFormatters` + Sidebar Category Filtering

**Files:**
- Modify: `Sources/App/ProjectorRunner.swift:4-27`
- Modify: `Sources/App/LauncherCardGridView.swift:5-31`
- Modify: `Tests/test_card_grid_view.swift`

**Interfaces:**
- Consumes: `LocalizationManager`, `AppLanguage`, `L10nKey`, `ExeItem`
- Produces:
  - `public enum SidebarFilter: String, CaseIterable, Identifiable` (`.all`, `.pinned`, `.recents`)
  - `CardGridFormatters.relativeTimeString(from date: Date, relativeTo now: Date = Date(), language: AppLanguage = LocalizationManager.shared.language) -> String`
  - `CardGridFormatters.filterItems(_ items: [ExeItem], query: String) -> [ExeItem]`
  - `CardGridFormatters.visibleItems(allItems: [ExeItem], filter: SidebarFilter, query: String) -> (pinned: [ExeItem], recents: [ExeItem])`
  - Localized `ProjectorRunnerError.errorDescription` using `LocalizationManager.shared`

- [ ] **Step 1: Update `Tests/test_card_grid_view.swift` with English default, Vietnamese relative time, and `SidebarFilter` assertions**

```swift
import Foundation

@main
struct CardGridViewTestRunner {
    static func main() throws {
        // 1. Test Filter Items by search query
        let item1 = ExeItem(name: "GS6_LV3_TESTING_01.exe", path: URL(fileURLWithPath: "/test/1.exe"), fileSizeFormatted: "5.4 MB", isPinned: true)
        let item2 = ExeItem(name: "Calculator_Flash.exe", path: URL(fileURLWithPath: "/test/2.exe"), fileSizeFormatted: "1.2 MB", isPinned: false)
        let item3 = ExeItem(name: "GS6_LV3_TRAINING_02.exe", path: URL(fileURLWithPath: "/test/3.exe"), fileSizeFormatted: "5.4 MB", isPinned: false)

        let all = [item1, item2, item3]

        assert(CardGridFormatters.filterItems(all, query: "").count == 3)
        assert(CardGridFormatters.filterItems(all, query: "gs6").count == 2)
        assert(CardGridFormatters.filterItems(all, query: "calc").first?.name == "Calculator_Flash.exe")
        assert(CardGridFormatters.filterItems(all, query: "nonexistent").isEmpty)

        // 2. Test SidebarFilter slicing + query
        let allSlice = CardGridFormatters.visibleItems(allItems: all, filter: .all, query: "")
        assert(allSlice.pinned.count == 1 && allSlice.recents.count == 2)

        let pinnedSlice = CardGridFormatters.visibleItems(allItems: all, filter: .pinned, query: "")
        assert(pinnedSlice.pinned.count == 1 && pinnedSlice.recents.isEmpty)

        let recentsSlice = CardGridFormatters.visibleItems(allItems: all, filter: .recents, query: "gs6")
        assert(recentsSlice.pinned.isEmpty && recentsSlice.recents.count == 1 && recentsSlice.recents[0].name == "GS6_LV3_TRAINING_02.exe")

        // 3. Test Relative Time Formatter in English (default) and Vietnamese
        let now = Date()
        assert(CardGridFormatters.relativeTimeString(from: now, relativeTo: now, language: .english) == "Just now")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-300), relativeTo: now, language: .english) == "5 min ago")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-7200), relativeTo: now, language: .english) == "2 hr ago")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-100000), relativeTo: now, language: .english) == "Yesterday")

        assert(CardGridFormatters.relativeTimeString(from: now, relativeTo: now, language: .vietnamese) == "Vừa mở")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-300), relativeTo: now, language: .vietnamese) == "5 phút trước")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-7200), relativeTo: now, language: .vietnamese) == "2 giờ trước")
        assert(CardGridFormatters.relativeTimeString(from: now.addingTimeInterval(-100000), relativeTo: now, language: .vietnamese) == "Hôm qua")

        // 4. Test ProjectorRunnerError localization in English and Vietnamese
        LocalizationManager.shared.language = .english
        assert(ProjectorRunnerError.projectorRuntimeMissing.errorDescription?.contains("Adobe Flash Player Projector runtime") == true)
        LocalizationManager.shared.language = .vietnamese
        assert(ProjectorRunnerError.projectorRuntimeMissing.errorDescription?.contains("Không tìm thấy nhân") == true)
        LocalizationManager.shared.language = .english

        print("All CardGrid tests passed successfully!")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -target x86_64-apple-macosx26.0 Sources/Core/LocalizationManager.swift Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/DefaultAppManager.swift Sources/Core/ExeLibraryStore.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Tests/test_card_grid_view.swift -o /tmp/test_card_grid && /tmp/test_card_grid`
Expected: FAIL (`extra argument 'language' in call`, `VisibleItems` / `SidebarFilter` not defined)

- [ ] **Step 3: Implement localized `ProjectorRunnerError` in `Sources/App/ProjectorRunner.swift` and `SidebarFilter` + `CardGridFormatters` in `Sources/App/LauncherCardGridView.swift`**

In `Sources/App/ProjectorRunner.swift`:
- Update `ProjectorRunnerError.errorDescription` to return `LocalizationManager.shared.string(...)` for `.projectorRuntimeMissing`, `.notAFlashExecutable`, `.fileUnreadable(msg)`, `.sessionFailed(msg)`, and `.launchFailed(msg)`.

In `Sources/App/LauncherCardGridView.swift`:
- Add `public enum SidebarFilter: String, CaseIterable, Identifiable { case all, pinned, recents; public var id: String { rawValue } }`.
- Update `CardGridFormatters.relativeTimeString(from:relativeTo:language:)` to resolve localized relative time strings via `LocalizationManager`.
- Add `CardGridFormatters.visibleItems(allItems: [ExeItem], filter: SidebarFilter, query: String) -> (pinned: [ExeItem], recents: [ExeItem])`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swiftc -target x86_64-apple-macosx26.0 Sources/Core/LocalizationManager.swift Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/DefaultAppManager.swift Sources/Core/ExeLibraryStore.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Tests/test_card_grid_view.swift -o /tmp/test_card_grid && /tmp/test_card_grid`
Expected: PASS (`All CardGrid tests passed successfully!`)

- [ ] **Step 5: Commit Task 2**

```bash
git add Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Tests/test_card_grid_view.swift
git commit -m "feat(core): localize ProjectorRunnerError and CardGridFormatters with SidebarFilter"
```

---

### Task 3: Standardize macOS 26+ Liquid Glass System UI & Language Switcher

**Files:**
- Modify: `Sources/App/LauncherCardGridView.swift`
- Modify: `Sources/App/LauncherWindowController.swift`
- Modify: `Sources/App/AppDelegate.swift`
- Modify: `Tests/test_fallback_routing.swift`

**Interfaces:**
- Consumes: `LocalizationManager`, `ExeLibraryStore`, `DefaultAppManager`, `SidebarFilter`, `CardGridFormatters`
- Produces:
  - `LauncherCardGridView` with `@available(macOS 26.0, *)` `NavigationSplitView` system layout:
    - Floating Liquid Glass Sidebar (`All Files`, `Pinned`, `Recents`, and bottom Default `.exe` Handler glass card with `GlassEffectContainer`, `.glassEffect`, `.buttonStyle(.glass)`).
    - Native `.searchable` and `.toolbar` with Language Switcher `Menu` (`EN` / `VI`), `Clear Recents` button, and `Add .exe File...` button (`.buttonStyle(.glassProminent)`).
    - Card Grid using `GlassEffectContainer`, `.glassEffect(.regular, in: .rect(cornerRadius: 16))`, `.buttonStyle(.glassProminent)` (`Run`), `.buttonStyle(.glass)` (`Show in Finder`, `Pin`).
  - Localized `LauncherWindowController` (window title, `NSOpenPanel`, `NSAlert`, and `macOS < 26` fallback UI with language switch button and `Combine` subscription to `LocalizationManager.shared.$language`).
  - Localized `AppDelegate` Finder open error alert.

- [ ] **Step 1: Expand `Tests/test_fallback_routing.swift` to verify window localization and live language switching**

Add assertions to `Tests/test_fallback_routing.swift` checking that:
```swift
LocalizationManager.shared.language = .english
let controller = LauncherWindowController()
assert(controller.window?.title == "Bug On Mac exe")
LocalizationManager.shared.language = .vietnamese
controller.applyLocalization()
assert(controller.window?.title == "Bug On Mac exe")
LocalizationManager.shared.language = .english
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swiftc -target x86_64-apple-macosx26.0 Sources/Core/LocalizationManager.swift Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/DefaultAppManager.swift Sources/Core/ExeLibraryStore.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_fallback_routing.swift -o /tmp/test_fallback && /tmp/test_fallback`
Expected: FAIL (`value of type 'LauncherWindowController' has no member 'applyLocalization'`)

- [ ] **Step 3: Implement macOS 26+ Liquid Glass `NavigationSplitView` in `Sources/App/LauncherCardGridView.swift` and localize `LauncherWindowController.swift` & `AppDelegate.swift`**

In `Sources/App/LauncherCardGridView.swift`:
- Observe `@ObservedObject private var l10n = LocalizationManager.shared` and `@ObservedObject private var store = ExeLibraryStore.shared`.
- Add `@State private var selectedFilter: SidebarFilter = .all`.
- On `#available(macOS 26.0, *)`, render `NavigationSplitView`:
  - **Sidebar:** `List(selection: $selectedFilter)` with `.all`, `.pinned`, `.recents` rows (SF Symbols `square.grid.2x2`, `pin.fill`, `clock.arrow.circlepath` + item count badges). Attach `.safeAreaInset(edge: .bottom)` containing a `GlassEffectContainer` status card showing Default `.exe` status dot + `l10n.string(isDefault ? .statusDefaultActive : .statusDefaultInactive)` and a `Button(l10n.string(.statusDefaultSetButton))` styled with `.buttonStyle(.glass)` inside `.glassEffect(.regular, in: .rect(cornerRadius: 12))`.
  - **Detail View:** `ScrollView` with `GlassEffectContainer(spacing: 14)` rendering the visible sections (`Pinned` and/or `Recents` based on `selectedFilter` and `searchText`) plus the `dropzoneCard` (when `selectedFilter != .pinned`).
  - **Cards (`cardView`):** On macOS 26+, style card container with `.glassEffect(.regular, in: .rect(cornerRadius: 16))`, Pin button with `.buttonStyle(.glass)` + `.buttonBorderShape(.circle)`, primary `Run` button with `.buttonStyle(.glassProminent)`, and `Show in Finder` button with `.buttonStyle(.glass)`. Display the file's icon via `NSWorkspace.shared.icon(forFile: item.path.path)` alongside an `"EXE"` / `"SWF"` pill badge.
  - **Native Toolbar & Search:** Attach `.searchable(text: $searchText, placement: .toolbar, prompt: Text(l10n.string(.toolbarSearchPlaceholder)))` and `.toolbar` with:
    - Language switcher `Menu` (`Label(l10n.language.shortCode, systemImage: "globe")`) offering `English` and `Tiếng Việt` with a checkmark on the active language.
    - `Clear Recents` button when `!store.recentItems.isEmpty && selectedFilter != .pinned`.
    - `Add .exe File...` button styled with `.buttonStyle(.glassProminent)`.

In `Sources/App/LauncherWindowController.swift` & `Sources/App/AppDelegate.swift`:
- Configure macOS 26+ window with `styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]` and `window.toolbarStyle = .unified`.
- Add `public func applyLocalization()` to `LauncherWindowController` and subscribe to `LocalizationManager.shared.$language` so all AppKit labels, buttons, and table column titles update immediately when language changes, plus a language toggle button in the fallback bottom bar.
- Replace all hardcoded Vietnamese strings in `DropContainerView`, `handleSetDefaultApp()`, `handleOpenPanel()`, `openAndRun()`, and `AppDelegate.handleFinderOpen()` with `LocalizationManager.shared.string(...)`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swiftc -target x86_64-apple-macosx26.0 Sources/Core/LocalizationManager.swift Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/DefaultAppManager.swift Sources/Core/ExeLibraryStore.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_fallback_routing.swift -o /tmp/test_fallback && /tmp/test_fallback`
Expected: PASS (`All Fallback routing tests passed successfully!`)

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_fallback_routing.swift
git commit -m "feat(ui): adopt macOS 26 Liquid Glass NavigationSplitView and toolbar language switcher"
```

---

### Task 4: Update Build Script & Bundle Verification Tests

**Files:**
- Modify: `scripts/build_app.sh:124-142`
- Modify: `Tests/test_bundle.swift`

**Interfaces:**
- Consumes: `Resources/en.lproj/Localizable.strings`, `Resources/vi.lproj/Localizable.strings`, `Sources/Core/LocalizationManager.swift`
- Produces: Installed `/Applications/Bug On Mac exe.app` bundle containing `en.lproj`, `vi.lproj`, `CFBundleDevelopmentRegion == "en"`, and compiled `BugOnMacExe` binary.

- [ ] **Step 1: Update `Tests/test_bundle.swift` to assert `CFBundleDevelopmentRegion == "en"` and `.lproj` resources exist in the installed bundle**

Add to `Tests/test_bundle.swift`:
```swift
assert(plist?["CFBundleDevelopmentRegion"] as? String == "en", "Default development region must be English (en)")
let localizations = plist?["CFBundleLocalizations"] as? [String] ?? []
assert(localizations.contains("en") && localizations.contains("vi"), "Bundle must declare en and vi localizations")

let enStrings = appURL.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings")
let viStrings = appURL.appendingPathComponent("Contents/Resources/vi.lproj/Localizable.strings")
assert(fm.fileExists(atPath: enStrings.path), "en.lproj/Localizable.strings must be bundled")
assert(fm.fileExists(atPath: viStrings.path), "vi.lproj/Localizable.strings must be bundled")
```

- [ ] **Step 2: Run `test_bundle.swift` before building to verify it fails**

Run: `swiftc -target x86_64-apple-macosx13.0 Tests/test_bundle.swift -o /tmp/test_bundle && /tmp/test_bundle`
Expected: FAIL (`Assertion failed: Default development region must be English (en)`)

- [ ] **Step 3: Update `scripts/build_app.sh` and run it to build and install the updated app bundle**

In `scripts/build_app.sh`:
- Copy `en.lproj` and `vi.lproj` into `$APP_BUNDLE/Contents/Resources/`:
  ```bash
  cp -R "$PROJ_ROOT/Resources/en.lproj" "$APP_BUNDLE/Contents/Resources/en.lproj"
  cp -R "$PROJ_ROOT/Resources/vi.lproj" "$APP_BUNDLE/Contents/Resources/vi.lproj"
  ```
- Add `"$PROJ_ROOT/Sources/Core/LocalizationManager.swift"` to the `swiftc` invocation and compile with `-target x86_64-apple-macosx13.0`.

- [ ] **Step 4: Run `scripts/build_app.sh` and all test suites to verify everything passes**

Run:
```bash
bash scripts/build_app.sh
swiftc -target x86_64-apple-macosx13.0 Tests/test_bundle.swift -o /tmp/test_bundle && /tmp/test_bundle
swiftc -target x86_64-apple-macosx13.0 Sources/Core/LocalizationManager.swift Tests/test_localization.swift -o /tmp/test_localization && /tmp/test_localization
swiftc -target x86_64-apple-macosx26.0 Sources/Core/LocalizationManager.swift Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/DefaultAppManager.swift Sources/Core/ExeLibraryStore.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Tests/test_card_grid_view.swift -o /tmp/test_card_grid && /tmp/test_card_grid
swiftc -target x86_64-apple-macosx26.0 Sources/Core/LocalizationManager.swift Sources/Core/ExeSwfExtractor.swift Sources/Core/SessionManager.swift Sources/Core/DefaultAppManager.swift Sources/Core/ExeLibraryStore.swift Sources/App/ProjectorRunner.swift Sources/App/LauncherCardGridView.swift Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_fallback_routing.swift -o /tmp/test_fallback && /tmp/test_fallback
```
Expected: All builds and test runners exit 0 with `PASSED`.

- [ ] **Step 5: Commit Task 4**

```bash
git add scripts/build_app.sh Tests/test_bundle.swift dist/
git commit -m "build: bundle en/vi lproj resources and compile LocalizationManager"
```
