# Thiết kế Rebrand "Bug On EXE", App Icon Chuẩn Apple HIG & Đóng Gói GitHub Release

## 1. Mục đích & Lý do (Intent and Why)
- **Định danh thương hiệu "Bug On EXE":** Đồng bộ tên ứng dụng trên toàn bộ mã nguồn, giao diện và gói cài đặt thành **"Bug On EXE"** (trong đó *"Bug On"* là thương hiệu chơi chữ đồng âm với *"Bất Ổn"*, kết hợp trực diện với chức năng chạy file `.EXE` trên macOS).
- **App Icon chuẩn Apple HIG (macOS 26 Liquid Glass):** Thay thế icon chữ `EXE` nền đỏ đơn giản hiện tại bằng thiết kế **Mẫu B (Công Tắc "Bug ON" Kính Lỏng)** tuân thủ [Apple Human Interface Guidelines — App Icons](https://developer.apple.com/design/human-interface-guidelines/app-icons): khung squircle liên tục (superellipse), bóng đổ chuẩn Dock macOS, và cấu trúc 3 lớp kính Liquid Glass có chiều sâu, khúc xạ ánh sáng và viền phản quang (specular highlight).
- **Phát hành GitHub & Bản tải về dùng ngay:** Đóng gói ứng dụng thành cả bộ cài `.dmg` và `.zip` (đã tích hợp sẵn nhân `Flash Player.app` và ký ad-hoc), đi kèm `README.md` và GitHub Actions workflow để người dùng tải về từ GitHub Releases là chạy được ngay.

---

## 2. Mục tiêu, Phi mục tiêu & Điều cần tránh (Goals, Non-Goals, Anti-Goals)

### Mục tiêu (Goals)
1. **Đổi tên toàn diện sang `Bug On EXE`:**
   - Gói ứng dụng: `Bug On EXE.app` (trong `dist/Bug On EXE.app` và `/Applications/Bug On EXE.app`).
   - Cấu hình `Resources/Info.plist`: `CFBundleName` và `CFBundleDisplayName` đổi thành `Bug On EXE`. (Giữ nguyên `CFBundleIdentifier` `com.stark.bugonmacexe` và `CFBundleExecutable` `BugOnMacExe` hoặc đồng bộ mượt mà để không làm gãy cấu hình LaunchServices hiện tại).
   - Chuỗi hiển thị đa ngôn ngữ (`Sources/Core/LocalizationManager.swift`, `Resources/en.lproj/Localizable.strings`, `Resources/vi.lproj/Localizable.strings`): Đổi toàn bộ `"Bug On Mac exe"` thành `"Bug On EXE"`.
   - Đường dẫn dự phòng trong `Sources/App/ProjectorRunner.swift`: kiểm tra `/Applications/Bug On EXE.app/Contents/Resources/Flash Player.app`.
   - Cập nhật toàn bộ bài kiểm thử trong `Tests/` (`test_bundle.swift`, `test_fallback_routing.swift`, `test_localization.swift`, v.v.) khớp với tên `"Bug On EXE"`.
2. **Thiết kế App Icon Mẫu B (Công Tắc "Bug ON" Kính Lỏng) chuẩn Apple HIG:**
   - Canvas chuẩn `1024×1024` (xuất đủ 10 file `.png` trong `AppIcon.iconset` từ `16x16` đến `512x512@2x` và đóng gói thành `AppIcon.icns`).
   - **Tỉ lệ lưới chuẩn macOS (Grid & Squircle):** Khung squircle chiếm ~`824×824` px trên canvas `1024×1024` (lề ngoài ~`9.76%`), bo góc liên tục cùng bóng đổ (Drop Shadow) phía dưới theo đúng hướng nguồn sáng từ trên xuống của macOS Dock.
   - **Cấu trúc 3 lớp Liquid Glass (Mẫu B):**
     - **Lớp 1 (Background):** Nền Slate/Midnight Squircle chuyển sắc sâu (`#0F172A` → `#1E293B`) với ánh sáng phản xạ nội vi và viền kính mảnh (specular border).
     - **Lớp 2 (Midground):** Rãnh công tắc (Toggle Switch Track) bằng kính xanh ngọc lục bảo (`#10B981` → `#059669`) ở trạng thái **ON**, có chữ `ON` phát sáng tinh tế bên trái.
     - **Lớp 3 (Foreground):** Núm gạt tròn nổi 3D bên phải chứa biểu tượng chú bọ đỏ cánh kính (Ruby Glass Bug), kết hợp tấm kính mờ (Frosted Glass Pill) mang nhãn `.EXE` sắc nét ở nửa dưới.
   - Xuất thêm 1 file ảnh preview chất lượng cao (`Resources/AppIcon-Preview.png`) để hiển thị ngay đầu trang `README.md` trên GitHub.
3. **Đóng gói Bản phân phối (`.dmg` + `.zip`) & Tài liệu GitHub:**
   - Tạo script `scripts/package_release.sh`:
     - Gọi `scripts/build_app.sh` để build và ký ad-hoc `Bug On EXE.app`.
     - Đóng gói `dist/Bug-On-EXE-macOS.zip` (dùng `ditto -c -k --sequesterRsrc --keepParent` để bảo toàn tuyệt đối quyền thực thi, symlink và chữ ký trong `.app`).
     - Đóng gói `dist/Bug-On-EXE-macOS.dmg` (chứa `Bug On EXE.app` và lối tắt `/Applications` để người dùng kéo-thả chuẩn macOS).
   - Tạo `README.md` song ngữ Việt - Anh trình bày rõ: Logo, tính năng chính, link tải bản Release, hướng dẫn cài đặt & mở lần đầu trên macOS.
   - Tạo `.github/workflows/release.yml` để tự động build và đính kèm `.dmg` + `.zip` lên GitHub Releases khi push tag `v*`.

### Phi mục tiêu (Non-Goals)
- Không thay đổi thuật toán bóc tách `.swf` từ `.exe` (`ExeSwfExtractor`) hay cơ chế chạy `Flash Player.app`.
- Không yêu cầu tài khoản Apple Developer trả phí ($99/năm); giữ cơ chế ký ad-hoc (`codesign --force --deep --sign -`) kèm hướng dẫn gỡ cách ly Gatekeeper gọn nhẹ trong `README.md`.

### Điều cần tránh (Anti-Goals)
- Không dùng `zip` thường làm hỏng symlink hoặc quyền thực thi bên trong `Flash Player.app` (bắt buộc dùng `ditto` và `hdiutil`).
- Không để sót tên cũ `"Bug On Mac exe"` trên giao diện người dùng hoặc thông báo lỗi.

---

## 3. Các hướng tiếp cận đã cân nhắc (Approaches)

| Phương án | Mô tả | Đánh đổi (Trade-offs) | Quyết định |
| :--- | :--- | :--- | :--- |
| **Phương án 1: Bộ đóng gói Kép (`.dmg` + `.zip`) tại máy kèm GitHub Actions tự động** | Đổi tên sang `Bug On EXE`, vẽ icon Mẫu B bằng CoreGraphics chuẩn Apple HIG, tạo `scripts/package_release.sh` xuất sẵn cả `.dmg` và `.zip` tại máy, thêm `README.md` và `.github/workflows/release.yml`. | **Ưu:** Có sẵn ngay file `.dmg` và `.zip` chuẩn macOS trên máy để kiểm thử hoặc kéo-thả lên GitHub Releases, đồng thời tự động hóa khi push tag qua GitHub Desktop.<br>**Nhược:** Cần viết thêm script tạo `.dmg` và workflow YAML. | **Đã chọn** |
| **Phương án 2: Chỉ nén `.zip` đơn giản trong `build_app.sh` và tự tạo Release thủ công** | Đổi tên và cập nhật icon Mẫu B, chỉ thêm lệnh nén `.zip` vào cuối `build_app.sh`. | **Ưu:** Ít file script hơn.<br>**Nhược:** Thiếu bộ cài `.dmg` kéo-thả quen thuộc của người dùng Mac và phải thao tác thủ công mỗi lần phát hành bản mới. | Loại bỏ |

---

## 4. Chi tiết quyết định thiết kế (The How)
1. **Tên gói & Hiển thị:**
   - Tên ứng dụng: `Bug On EXE` (`Bug On EXE.app`).
   - Dọn dẹp bản cài đặt cũ `/Applications/Bug On Mac exe.app` trong quá trình chạy `build_app.sh` để tránh trùng lặp 2 app trong LaunchServices/Open With menu.
2. **Kiến trúc vẽ Icon Mẫu B (CoreGraphics Vector trong `build_app.sh`):**
   - Sử dụng `NSBezierPath` và `CGContext` vẽ theo hệ tọa độ tỉ lệ phần trăm (`0.0` → `1.0` của `px`), đảm bảo sắc nét tuyệt đối ở mọi kích thước từ `16×16` đến `1024×1024`:
     - Đổ bóng ngoài (ambient + key drop shadow) bên dưới squircle.
     - Vẽ squircle nền Slate/Midnight gradient + viền kính sáng phía trên.
     - Vẽ công tắc (Switch Track) màu xanh Emerald ở nửa trên cùng chữ `ON` (ẩn chữ `ON` ở kích thước siêu nhỏ `≤ 32px` để tránh rối mắt, đúng khuyến nghị của Apple HIG).
     - Vẽ núm gạt tròn nổi 3D bên phải với họa tiết chú bọ đỏ cánh kính (Ruby Glass Bug).
     - Vẽ thẻ kính mờ (Frosted Glass Pill) mang chữ `.EXE` ở nửa dưới.
3. **Đóng gói bản phân phối (`scripts/package_release.sh`):**
   - Xuất ra `dist/Bug-On-EXE-macOS.zip` và `dist/Bug-On-EXE-macOS.dmg`.
   - Kiểm tra tự động tính toàn vẹn của gói `.app` bên trong `.dmg` và `.zip`.

---

## 5. Phần dành cho Builder quyết định (What's Left to the Builder)
- Tinh chỉnh tọa độ bezier, độ mờ bóng đổ (shadow blur/alpha) và màu gradient chi tiết của chú bọ trên núm công tắc để đạt độ nổi khối Liquid Glass đẹp nhất.
- Bố cục trình bày chi tiết trong `README.md`.
