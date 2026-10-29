# Liquid Glass Card Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuyển đổi giao diện `Bug On Mac exe` từ bảng danh sách cố định (hardcoded IC3) sang trình quản lý dạng lưới thẻ hiện đại với hiệu ứng Liquid Glassmorphism trên macOS >= 26, đồng thời tự động fallback an toàn về giao diện bảng danh sách chuẩn trên macOS < 26.

**Architecture:** Sử dụng kiến trúc kết hợp AppKit và SwiftUI. Xây dựng model `ExeLibraryStore` để lưu trữ bền vững danh sách file `.exe` (Pinned và Recents). Dựng view `LauncherCardGridView` bằng SwiftUI với native materials (`.ultraThinMaterial`, glassmorphic cards, gradient specularity, hover/drag-drop). `LauncherWindowController` kiểm tra `ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26` để quyết định nạp SwiftUI Liquid Glass qua `NSHostingController` hay giữ lại bảng chuẩn `NSTableView`.

**Tech Stack:** Swift 5+, AppKit, SwiftUI (`NSHostingController`, `LazyVGrid`, `.ultraThinMaterial`, `UniformTypeIdentifiers`), macOS LaunchServices.

**Spec:** `docs/superpowers/specs/2026-10-29-liquid-glass-card-launcher-design.md`

## Global Constraints

- Hỗ trợ macOS 26.7.2 (`x86_64`) đầy đủ hiệu ứng Liquid Glassmorphism.
- Bắt buộc kiểm tra `majorVersion >= 26` và fallback về giao diện bảng chuẩn nếu chạy trên macOS < 26.
- Giữ nguyên 100% logic trích xuất SWF (`ExeSwfExtractor`) và nhân Adobe Flash Projector 32 (`ProjectorRunner`).
- Không để xảy ra rò rỉ session hay xung đột kéo-thả nhiều file.

## Review Focus

- File `.exe` trong danh sách đã bị di chuyển hoặc xóa ngoài Finder: hiển thị trạng thái mờ hoặc cảnh báo "Không tìm thấy file" thay vì crash.
- Mở liên tiếp nhiều file `.exe` qua Finder khi ứng dụng chưa chạy: `ExeLibraryStore` phải nạp và cập nhật từng file an toàn không bị race condition.
- Kéo thả file không hợp lệ (không phải đuôi `.exe` hoặc `.swf`): giao diện Dropzone từ chối và hiển thị thông báo lỗi rõ ràng.
- Chế độ Dark Mode / Light Mode thay đổi tức thì: hiệu ứng Liquid Glass (`.ultraThinMaterial`) và viền kính phản quang phải thích ứng mượt mà.
- Fallback macOS < 26: logic phân nhánh giao diện không làm crash do thiếu thuộc tính hay API mới.

---

### Task 1: Xây dựng Mô hình Quản lý Thư viện Tập tin (`ExeLibraryStore`)

**Files:**
- Create: `Sources/Core/ExeLibraryStore.swift`
- Test: `Tests/test_library_store.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct ExeItem: Identifiable, Codable, Equatable {
      public let id: UUID
      public let name: String
      public let path: URL
      public var fileSizeFormatted: String
      public var lastOpened: Date
      public var isPinned: Bool
      public var existsOnDisk: Bool { get }
  }

  public final class ExeLibraryStore: ObservableObject {
      public static let shared: ExeLibraryStore
      @Published public private(set) var items: [ExeItem]
      public var pinnedItems: [ExeItem] { get }
      public var recentItems: [ExeItem] { get }
      public func addOrUpdate(url: URL, isPinned: Bool? = nil)
      public func togglePin(id: UUID)
      public func remove(id: UUID)
      public func clearRecents()
      public func cleanMissingFiles()
  }
  ```

- [ ] **Step 1: Viết test kiểm tra `ExeLibraryStore`**

Tạo file `Tests/test_library_store.swift` kiểm tra:
1. Thêm file mới vào store -> file xuất hiện trong `recentItems`.
2. Ghim file (`togglePin`) -> file chuyển sang `pinnedItems`.
3. Cập nhật file đã có -> cập nhật `lastOpened` thay vì nhân bản item.
4. Xóa recents (`clearRecents`) -> chỉ xóa file chưa ghim, giữ nguyên file pinned.
5. Lưu trữ và đọc lại từ bộ nhớ (Persistence verification).

- [ ] **Step 2: Chạy test để xác nhận test thất bại (Red)**

Chạy: `swift -I Sources/Core Sources/Core/ExeLibraryStore.swift Tests/test_library_store.swift`
Kỳ vọng: Lỗi biên dịch vì chưa có `ExeLibraryStore.swift`.

- [ ] **Step 3: Triển khai `ExeLibraryStore.swift`**

Viết code trong `Sources/Core/ExeLibraryStore.swift`:
- Cung cấp model `ExeItem` tuân thủ `Codable`.
- Lưu trữ danh sách vào `~/Library/Application Support/BugOnMacExe/library.json`.
- Triển khai đầy đủ các hàm `addOrUpdate`, `togglePin`, `remove`, `clearRecents`, `cleanMissingFiles`.

- [ ] **Step 4: Chạy test để xác nhận test vượt qua (Green)**

Chạy: `swift -I Sources/Core Sources/Core/ExeLibraryStore.swift Tests/test_library_store.swift`
Kỳ vọng: PASS (thoát mã 0, không có assertion failure).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/ExeLibraryStore.swift Tests/test_library_store.swift
git commit -m "feat: add ExeLibraryStore for pinned and recent exe file management"
```

---

### Task 2: Xây dựng Giao diện SwiftUI Liquid Glass Card Launcher (`LauncherCardGridView`)

**Files:**
- Create: `Sources/App/LauncherCardGridView.swift`
- Test: `Tests/test_card_grid_view.swift`

**Interfaces:**
- Consumes: `ExeLibraryStore`, `ExeItem`, `ProjectorRunner`, `DefaultAppManager`
- Produces:
  ```swift
  public struct LauncherCardGridView: View {
      public init(onOpenFilePicker: @escaping () -> Void, onRunFile: @escaping (URL) -> Void)
  }
  ```

- [ ] **Step 1: Viết test kiểm thử các logic render và bộ lọc của View**

Tạo file `Tests/test_card_grid_view.swift` kiểm tra:
1. Bộ lọc tìm kiếm (`filterText`): chỉ trả về các thẻ có tên khớp từ khóa.
2. Kiểm tra format hiển thị kích thước file và thời gian tương đối ("Vừa mở", "x phút trước", "Hôm qua").

- [ ] **Step 2: Chạy test để xác nhận test thất bại (Red)**

Chạy: `swift Tests/test_card_grid_view.swift`
Kỳ vọng: Thất bại do chưa có file hoặc method.

- [ ] **Step 3: Triển khai `LauncherCardGridView.swift` với Liquid Glassmorphism**

Viết code trong `Sources/App/LauncherCardGridView.swift`:
- Áp dụng nền `.ultraThinMaterial` và bo tròn góc mượt mà cho toàn cửa sổ.
- Thanh công cụ trên (Top Bar): Glass pill badge hiển thị trạng thái ứng dụng mặc định kèm nút gán, ô tìm kiếm kính mờ, nút "+ Thêm file .exe...".
- Phần **★ Đã ghim (Pinned)**: Lưới `LazyVGrid` hiển thị các thẻ kính mờ có gradient icon, tên bài, nút `▶ Khởi chạy`, nút `📁 Finder` và icon `★`.
- Phần **🕒 Gần đây (Recents)**: Lưới `LazyVGrid` hiển thị các file vừa mở và nút dọn dẹp lịch sử.
- Thẻ **Dropzone (＋ Thêm file .exe)**: Thẻ nét đứt kính mờ hỗ trợ kéo-thả file `.exe` từ Finder.
- Hỗ trợ Double-click vào thẻ để chạy ngay lập tức.

- [ ] **Step 4: Chạy test và biên dịch thử nghiệm (Green)**

Chạy: `swiftc -c -target x86_64-apple-macosx13.0 Sources/Core/ExeLibraryStore.swift Sources/Core/DefaultAppManager.swift Sources/App/LauncherCardGridView.swift -o /tmp/card_grid.o`
Kỳ vọng: Biên dịch thành công mã 0.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/LauncherCardGridView.swift Tests/test_card_grid_view.swift
git commit -m "feat: add Liquid Glass card grid launcher SwiftUI view"
```

---

### Task 3: Tích hợp Cửa sổ, Fallback macOS < 26 và Tự động Ghi nhận từ Finder

**Files:**
- Modify: `Sources/App/LauncherWindowController.swift`
- Modify: `Sources/App/AppDelegate.swift`
- Test: `Tests/test_fallback_routing.swift`

**Interfaces:**
- Consumes: `LauncherCardGridView`, `ExeLibraryStore`, `AppDelegate`
- Produces: Phân nhánh hiển thị tự động:
  ```swift
  if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 {
      // Liquid Glass Card Grid qua NSHostingController
  } else {
      // Fallback về bảng danh sách chuẩn
  }
  ```

- [ ] **Step 1: Viết test kiểm tra logic phân nhánh fallback theo hệ điều hành**

Tạo file `Tests/test_fallback_routing.swift` kiểm tra:
1. Hàm helper `shouldUseLiquidGlass(majorVersion: Int) -> Bool` trả về `true` khi `>= 26` và `false` khi `< 26`.
2. `AppDelegate` khi nhận sự kiện `application(_:openFiles:)` tự động thêm URL vào `ExeLibraryStore.shared`.

- [ ] **Step 2: Chạy test để xác nhận test thất bại (Red)**

Chạy: `swift Tests/test_fallback_routing.swift`
Kỳ vọng: Thất bại do chưa cập nhật `LauncherWindowController`.

- [ ] **Step 3: Cập nhật `LauncherWindowController.swift` và `AppDelegate.swift`**

- Trong `LauncherWindowController.swift`:
  - Loại bỏ hoàn toàn đường dẫn hardcode `~/Documents/IC3`.
  - Cấu hình cửa sổ tràn viền (`.fullSizeContentView`, `titlebarAppearsTransparent = true`).
  - Phân nhánh: nếu `majorVersion >= 26` thì set `contentViewController = NSHostingController(rootView: LauncherCardGridView(...))`, ngược lại dùng giao diện bảng `NSTableView` chuẩn làm fallback.
- Trong `AppDelegate.swift`:
  - Khi người dùng double-click mở file từ Finder, tự động gọi `ExeLibraryStore.shared.addOrUpdate(url: url)`.

- [ ] **Step 4: Chạy test xác nhận vượt qua (Green)**

Chạy: `swift Tests/test_fallback_routing.swift`
Kỳ vọng: PASS (mã 0).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/LauncherWindowController.swift Sources/App/AppDelegate.swift Tests/test_fallback_routing.swift
git commit -m "feat: integrate Liquid Glass hosting, OS fallback, and Finder sync"
```

---

### Task 4: Cập nhật Build Script, Đóng gói Bundle và Kiểm thử Toàn diện

**Files:**
- Modify: `scripts/build_app.sh`
- Test: Toàn bộ suite test trong `Tests/` và khởi chạy `/Applications/Bug On Mac exe.app`

- [ ] **Step 1: Cập nhật `scripts/build_app.sh` để thêm các file nguồn mới vào lệnh biên dịch `swiftc`**

Thêm `Sources/Core/ExeLibraryStore.swift` và `Sources/App/LauncherCardGridView.swift` vào danh sách biên dịch của `swiftc`.

- [ ] **Step 2: Chạy toàn bộ test suites**

Chạy:
```bash
for t in Tests/test_*.swift; do
    echo "Running $t..."
    swift -I Sources/Core "$t"
done
```
Kỳ vọng: Tất cả các file test chạy thành công không có lỗi.

- [ ] **Step 3: Biên dịch, ký số và cài đặt ứng dụng vào `/Applications/Bug On Mac exe.app`**

Chạy: `bash scripts/build_app.sh`
Kỳ vọng:
- Biên dịch thành công `BugOnMacExe` nhúng SwiftUI và AppKit.
- Ký số ad-hoc hợp lệ (`codesign --verify`).
- Cài đặt thành công vào `/Applications/Bug On Mac exe.app`.

- [ ] **Step 4: Chạy thử nghiệm mở ứng dụng trực tiếp**

Chạy: `open "/Applications/Bug On Mac exe.app"`
Kỳ vọng: Cửa sổ Liquid Glass Card Launcher hiển thị mượt mà trên macOS 26.7.2, hiển thị đầy đủ các thẻ Pinned, Recents và Dropzone.

- [ ] **Step 5: Commit**

```bash
git add scripts/build_app.sh
git commit -m "build: bundle ExeLibraryStore and Liquid Glass launcher into release"
```
