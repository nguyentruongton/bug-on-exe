<p align="center">
  <img src="Resources/AppIcon-Preview.png" width="160" height="160" alt="Bug On EXE App Icon" />
</p>

<h1 align="center">Bug On EXE</h1>

<p align="center">
  <strong>Chạy trực tiếp các file bài thi &amp; ứng dụng Adobe Flash <code>.exe</code> / <code>.swf</code> (như IC3 GS6) ngay trên macOS bằng một cú double-click.</strong><br/>
  <em>Run portable Adobe Flash Projector <code>.exe</code> &amp; <code>.swf</code> files natively on macOS with a single double-click.</em>
</p>

---

## 🐞 Về tên gọi "Bug On EXE" (About the Brand)

**Bug On** là lối chơi chữ đồng âm tiếng Việt của **"Bất Ổn"** kết hợp với thuật ngữ lập trình **Bug** và công tắc đang bật **ON**. Việc một chiếc máy Mac mở và chạy mượt mà file `.exe` của Windows vốn là một pha xử lý nghe rất *"bất ổn"*, nhưng **Bug On EXE** biến điều đó thành trải nghiệm tự nhiên như một ứng dụng gốc trên macOS.

---

## ✨ Tính năng nổi bật (Key Features)

- **Mở trực tiếp khi Double-click (`.exe` & `.swf`):** Đăng ký làm ứng dụng mặc định trên Finder chỉ với 1 nút bấm (`Set as Default`).
- **Tương thích 100% ActionScript 3 / Adobe Flex (IC3 GS6):** Bóc tách tức thì payload `.swf` từ file `.exe` (hỗ trợ cả chữ ký chuẩn `0xFA123456` lẫn quét sâu PE32) và khởi chạy bằng nhân **Adobe Flash Player Projector 32 (64-bit macOS)** tích hợp sẵn bên trong gói ứng dụng.
- **Tự động cấu hình bảo mật (`FlashPlayerTrust`) & Tài nguyên đi kèm:** Không bao giờ bị chặn bởi hộp thoại sandbox của Flash; tự động liên kết các file XML/âm thanh đi kèm cùng thư mục với file `.exe`.
- **Giao diện macOS 26 Liquid Glass & Đa ngôn ngữ (`EN` / `VI`):** Quản lý danh sách bài thi, ghim bài quan trọng (`Pinned`), tìm kiếm nhanh và chuyển đổi tức thì giữa Tiếng Anh & Tiếng Việt.

---

## 🚀 Tải về & Sử dụng ngay (Download & Quick Start)

1. Vào mục [**Releases**](../../releases) ở khung bên phải trang GitHub này.
2. Tải một trong hai bản phân phối:
   - **`Bug-On-EXE-macOS.dmg`** *(Khuyên dùng)*: Mở file `.dmg` và kéo **Bug On EXE.app** vào thư mục **Applications**.
   - **`Bug-On-EXE-macOS.zip`**: Giải nén và chép **Bug On EXE.app** vào `/Applications`.
3. **Lưu ý khi mở lần đầu trên macOS (Gatekeeper):**
   Vì ứng dụng được ký ad-hoc miễn phí (không qua Apple Developer ID trả phí), nếu macOS báo *"unidentified developer"*, bạn chỉ cần chạy lệnh sau trong **Terminal** (hoặc chuột phải chọn **Open**):
   ```bash
   xattr -cr "/Applications/Bug On EXE.app"
   ```
4. Mở **Bug On EXE**, bấm **Set as Default** (Đặt mặc định), từ đó về sau chỉ cần double-click vào bất kỳ file `.exe` Flash nào trong Finder để chạy ngay!

---

## 🛠️ Tự biên dịch từ mã nguồn (Build from Source)

Yêu cầu: macOS 13.0+ (Intel `x86_64` hoặc Apple Silicon chạy Rosetta 2) và Xcode Command Line Tools (`swiftc`).

```bash
# 1. Build và cài đặt trực tiếp vào /Applications/Bug On EXE.app
bash scripts/build_app.sh

# 2. Đóng gói bộ cài đặt Release (dist/Bug-On-EXE-macOS.dmg & dist/Bug-On-EXE-macOS.zip)
bash scripts/package_release.sh
```
