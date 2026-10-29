# Thiết kế Giao diện Liquid Glass Card Launcher cho "Bug On Mac exe"

## 1. Mục đích & Lý do (Intent and Why)
- Nâng cấp ứng dụng từ một công cụ có giao diện bảng danh sách cố định (hardcoded thư mục IC3) thành một tiện ích độc lập, tổng quát cho macOS.
- Giao diện trung tâm được thiết kế theo phong cách hiện đại nhất (**Liquid Glassmorphism**) dạng lưới thẻ (App Card Grid), giúp người dùng quản lý trực quan các file Windows `.exe` nhẹ (nhúng Flash/SWF) từng chạy hoặc chủ động thêm/ghim vào thư viện.

---

## 2. Mục tiêu, Phi mục tiêu & Điều cần tránh (Goals, Non-Goals, Anti-Goals)

### Mục tiêu (Goals)
1. **Loại bỏ hardcode IC3:** Xóa bỏ cơ chế quét cố định thư mục `~/Documents/IC3`.
2. **Quản lý tập tin linh hoạt (`ExeLibraryStore`):**
   - Lưu trữ danh sách file gồm: `id`, `name`, `path`, `fileSize`, `lastOpenedDate`, `isPinned`.
   - Phân loại rõ: **Đã ghim (Pinned)** và **Mở gần đây (Recents)**.
   - Tự động ghi nhớ khi mở file từ Finder hoặc kéo-thả vào cửa sổ.
   - Lưu trữ bền vững vào `~/Library/Application Support/BugOnMacExe/library.json` hoặc `UserDefaults`.
3. **Giao diện Liquid Glassmorphism & Cơ chế Fallback:**
   - **Trên macOS >= 26:** Kích hoạt giao diện **Liquid Glassmorphism** (cửa sổ kính mờ tràn viền `fullSizeContentView`, nền `.ultraThinMaterial`, các thẻ card bóng kính mờ glassmorphic có viền phản quang specular highlight và hiệu ứng hover mượt mà).
   - **Trên macOS < 26 (Fallback):** Tự động nhận diện phiên bản hệ điều hành (`ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26`) để fallback an toàn về giao diện bảng danh sách chuẩn (Standard Table/Clean UI) hiện có, tránh lỗi thiếu API hoặc giật lag/lỗi hiển thị kính mờ trên các bản macOS cũ.
4. **Tương tác chuẩn macOS:**
   - Double-click vào thẻ để chạy bài ngay lập tức.
   - Nút `▶ Khởi chạy`, nút `📁 Hiện trong Finder`, nút ghim/bỏ ghim `★`.
   - Hỗ trợ Kéo-thả (Drag & Drop) file `.exe` trực tiếp vào cửa sổ / ô dropzone để nạp hoặc chạy ngay.
   - Ô tìm kiếm nhanh theo tên file.
   - Nút/Huy hiệu trạng thái ứng dụng mặc định `.exe`.

### Phi mục tiêu (Non-Goals)
- Thay đổi logic bóc tách SWF và nhân chạy Flash Projector (giữ nguyên 100% tầng core `ExeSwfExtractor` và `ProjectorRunner`).
- Chỉnh sửa nội dung file `.exe`.

### Điều cần tránh (Anti-Goals)
- Không dùng giao diện bảng danh sách cổ điển đơn điệu.
- Không làm giật lag hiệu ứng kính mờ (Liquid Glass) khi cuộn danh sách nhiều file.

---

## 3. Ràng buộc kỹ thuật (Constraints)
- Môi trường: macOS 26.7.2 (`x86_64`), hỗ trợ đầy đủ các API SwiftUI hiện đại và Materials (`.ultraThinMaterial`, `Material`, `LinearGradient`).
- Mã nguồn: Swift 5+, biên dịch trực tiếp qua `swiftc` / script đóng gói hiện có của dự án.
- Tương thích ngược: Khi double-click từ Finder, app vẫn chạy ngầm mượt mà và đóng Launcher theo cơ chế `postFinderOpenDisposition`.

---

## 4. Các hướng tiếp cận đã cân nhắc (Approaches)

| Hướng tiếp cận | Đánh đổi (Trade-offs) | Lựa chọn |
| :--- | :--- | :--- |
| **Hướng 1: SwiftUI nhúng qua `NSHostingController` với Native Materials (Liquid Glass)** | Tận dụng SwiftUI để tạo hiệu ứng kính mờ (Liquid Glass), thẻ bóng kính, gradient, LazyVGrid và thao tác kéo-thả tự nhiên nhất. Code ngắn gọn, chuẩn macOS hiện đại. | **Đã chọn** (Đáp ứng hoàn hảo yêu cầu giao diện mới nhất và hiệu ứng Liquid Glass). |
| **Hướng 2: AppKit thuần `NSCollectionView`** | Dựng hoàn toàn bằng AppKit. Rất khó tạo hiệu ứng kính mờ Liquid Glass trên từng item cell mà không gây lỗi dựng hình; code rườm rà. | Loại bỏ |
| **Hướng 3: AppKit `NSStackView` trong `NSScrollView`** | Đơn giản nhưng hiệu năng kém khi co giãn cửa sổ và hiệu ứng mờ hạn chế. | Loại bỏ |

---

## 5. Quyết định kiến trúc & Chi tiết triển khai

### 5.1. Mô hình dữ liệu (`ExeItem` & `ExeLibraryStore`)
- `ExeItem`: `id`, `name`, `path: URL`, `fileSizeFormatted: String`, `lastOpened: Date`, `isPinned: Bool`, `existsOnDisk: Bool`.
- `ExeLibraryStore: ObservableObject`:
  - `items: [ExeItem]`
  - `pinnedItems`: Lọc các item có `isPinned == true`.
  - `recentItems`: Lọc các item còn lại, sắp xếp theo `lastOpened` giảm dần (tối đa 20 file).
  - Các hàm thao tác: `addOrUpdate(url: URL)`, `togglePin(item: ExeItem)`, `remove(item: ExeItem)`, `clearRecents()`, `cleanMissingFiles()`.

### 5.2. Giao diện Liquid Glass & Điều kiện Fallback
- **Kiểm tra phiên bản hệ điều hành:**
  ```swift
  let isLiquidGlassSupported = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
  ```
- **Trên macOS >= 26:** 
  - Khởi tạo `NSHostingController(rootView: LauncherCardGridView())`.
  - Cửa sổ `NSWindow`:
    - `styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`
    - `titlebarAppearsTransparent = true`
    - Nền mờ kính: `NSVisualEffectView` kết hợp SwiftUI `.background(.ultraThinMaterial)`.
  - Thanh công cụ trên (Top Bar):
    - Trạng thái Default App (`DefaultAppManager.isDefaultApp()`) hiển thị dưới dạng viên thuốc kính mờ (Glass pill badge) kèm nút đổi nếu chưa bật.
    - Ô tìm kiếm kính mờ với icon kính lúp.
    - Nút "+ Thêm file .exe".
  - Lưới thẻ (`LazyVGrid`):
    - Thẻ Pinned: Glass card với viền sáng mờ, icon huy hiệu màu cam đỏ gradient, tên file, dung lượng, thời gian, nút Play và nút Finder.
    - Thẻ Recents: Glass card hiển thị các bài vừa chạy.
    - Thẻ Dropzone: Viền nét đứt phát sáng nhẹ khi hover/drag file vào.
  - Tương tác:
    - Double-click vào thẻ gọi `ProjectorRunner.run(fileURL: item.path)`.
- **Trên macOS < 26 (Fallback):**
  - Giữ lại view bảng danh sách cổ điển (`NSTableView`) hoặc một layout AppKit chuẩn để đảm bảo ứng dụng luôn hiển thị ổn định, không lỗi trên các phiên bản macOS cũ hơn.

### 5.3. Trách nhiệm dành cho Builder
- Tạo file `Sources/Core/ExeLibraryStore.swift`.
- Tạo file `Sources/App/LauncherCardGridView.swift` sử dụng SwiftUI với hiệu ứng Liquid Glass.
- Cập nhật `LauncherWindowController.swift` để kiểm tra phiên bản hệ điều hành (`majorVersion >= 26`) và tải `LauncherCardGridView` (Liquid Glass) hoặc fallback về `NSTableView`.
- Cập nhật `AppDelegate.swift` để tự động gọi `ExeLibraryStore.shared.addOrUpdate(url:)` mỗi khi có file mở qua Finder.
- Cập nhật kịch bản build/test để đảm bảo biên dịch và ký số hoàn chỉnh.
