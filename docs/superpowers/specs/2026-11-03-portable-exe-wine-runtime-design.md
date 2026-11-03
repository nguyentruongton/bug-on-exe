# Thiết kế Nâng cấp Hỗ trợ Chạy File `.exe` Portable (7-Zip SFX & Win32) Kèm Tải Ngầm Nhân Wine

## 1. Mục đích & Lý do (Intent and Why)
- **Mở rộng từ Flash sang Game & Ứng dụng Portable Windows (`.exe`):** Hiện tại **Bug On EXE** chỉ bóc tách nội dung Adobe Flash (`.swf`) bên trong file `.exe` để chạy bằng `Flash Player.app` tích hợp sẵn. Khi người dùng mở các game giải lao phổ biến như `Plants_Vs_Zombies.exe`, `Zuma.exe`, `AngryBirds.exe`, `Feeding Frenzy 2 Deluxe.exe` hay `stress.exe`, ứng dụng báo lỗi *"File .exe này không chứa nội dung Adobe Flash Projector"*.
- **Giữ nguyên bộ cài gốc siêu nhẹ (~18MB), chỉ tải Wine khi cần:** Thay vì nhúng sẵn nhân Wine (~600MB) làm phình bộ cài cho người chỉ làm bài thi IC3 Flash, **Bug On EXE** hoạt động như một **Bộ định tuyến thông minh (Smart Router)**:
  - Nếu là file Flash `.exe` / `.swf` → Chạy ngay bằng nhân `Flash Player.app` gốc của macOS (0.2 giây, không cần mạng hay Wine).
  - Nếu là file Windows Portable `.exe` → Kiểm tra máy đã có Wine chưa. Nếu chưa, hiện hộp thoại xác nhận và **tải + cài đặt ngầm nhân Wine ngay trong ứng dụng kèm thanh tiến trình**, sau đó tự động mở game.
- **Khắc phục triệt để nhược điểm của gói Portable 7-Zip SFX trên Wine gốc:** Các game portable như `Plants_Vs_Zombies.exe` được đóng gói bằng `7z SFX Constructor` với cấu hình giải nén tạm vào `%Temp%`, gọi `PreExtract="... cmd /c KillDuplicate.cmd"` và xóa sạch khi thoát (`Delete="%%T"`). Nếu giao thẳng cho Wine gốc chạy sẽ bị treo ở `KillDuplicate.cmd`, tốn thời gian giải nén lại mỗi lần mở và mất sạch file save tiến trình chơi. **Bug On EXE** giải quyết bằng cách cắt phần lõi `7z` và giải nén một lần duy nhất bằng `/usr/bin/tar` của macOS vào thư mục cố định trước khi gọi Wine chạy file thực thi chính.

---

## 2. Mục tiêu, Phi mục tiêu & Điều cần tránh (Goals, Non-Goals, Anti-Goals)

### Mục tiêu (Goals)
1. **Phân loại & Bóc tách Đa định dạng `.exe` (`PortableExeExtractor`):**
   - **Ưu tiên 1 — Flash Projector (`.flash`):** Gọi `ExeSwfExtractor.extract(from:)` hiện có. Nếu tìm thấy payload `FWS`/`CWS`/`ZWS`, giữ nguyên luồng chạy `Flash Player.app`.
   - **Ưu tiên 2 — Gói 7-Zip SFX Portable (`.sevenZipSfx`):** Nếu file có chữ ký `MZ` (`0x4D, 0x5A`) ở đầu và chứa chữ ký `7z` (`[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]`) ở offset `> 0`:
     - Đọc khối cấu hình `;!@Install@!UTF-8! ... ;!@InstallEnd@!` (nếu có) để trích xuất giá trị `RunProgram="..."` (loại bỏ ký tự escape `\"` và tiền tố `%%T\\` nếu có).
     - Ghi nhận `archiveOffset` (vị trí bắt đầu chữ ký `7z`) và `runProgram`.
   - **Ưu tiên 3 — File thực thi Windows thuần (`.standaloneWin32`):** Nếu file có header PE (`MZ`) hợp lệ nhưng không chứa Flash hay 7z SFX (ví dụ `stress.exe`).
2. **Giải nén Lưu trữ Cố định cho Gói 7-Zip SFX (`PortableSessionManager`):**
   - Lưu tại `~/Library/Application Support/BugOnExe/PortableApps/<fnv1aHash>-<baseName>/`.
   - **Cơ chế Cache & Giữ File Save:** Nếu thư mục đích đã có file đánh dấu `.extracted_ok` và file `.exe` đích bên trong vẫn tồn tại, tái sử dụng ngay lập tức mà không giải nén lại (giúp mở game lần 2 dưới 1 giây và bảo toàn thư mục save game).
   - **Giải nén lần đầu:**
     - Trích xuất dải byte từ `archiveOffset` đến hết file ra một file tạm `payload.7z`.
     - Gọi `/usr/bin/tar -xf payload.7z -C <targetDir>` (tận dụng `libarchive` tích hợp sẵn trên mọi máy macOS để giải nén định dạng `7z`).
     - Xóa `payload.7z` và xóa file `KillDuplicate.cmd` (nếu có) để loại bỏ script gây treo.
     - Xác định file `.exe` thực thi chính trong `<targetDir>`:
       1. Khớp theo tên `runProgram` từ cấu hình SFX (không phân biệt hoa thường).
       2. Nếu không có `runProgram` hoặc không tìm thấy: quét trong `<targetDir>` (tối đa 2 cấp thư mục) để chọn file `.exe` (bỏ qua các file `unins*`, `setup*`), ưu tiên file trùng tên với file gốc hoặc có dung lượng lớn nhất.
     - Ghi đường dẫn tương đối của file `.exe` đích vào `.extracted_ok`.
3. **Quản lý, Tự động Tải & Cài đặt Ngầm Nhân Wine (`WineRuntimeManager` & `WineInstallProgressWindowController`):**
   - **Phát hiện Wine sẵn có (`locateWineBinary()`):** Kiểm tra theo thứ tự ưu tiên:
     1. Bản cài đặt do app quản lý tại `~/Library/Application Support/BugOnExe/Runtime/` (quét `Wine Devel.app`, `Wine Stable.app`, `Wine Staging.app`, `Wine Crossover.app` → `Contents/Resources/wine/bin/wine` hoặc `wine64`).
     2. Bản cài đặt trong `/Applications/` (`Wine Stable.app`, `Wine Devel.app`, `Wine Staging.app`, `Wine Crossover.app`).
     3. Đường dẫn CLI hệ thống (`/opt/homebrew/bin/wine`, `/usr/local/bin/wine`, `/opt/homebrew/bin/wine64`, `/usr/local/bin/wine64`).
   - **Hộp thoại xác nhận & Cửa sổ Thanh tiến trình tải ngầm:**
     - Khi người dùng mở file `.exe` Windows mà `locateWineBinary()` trả về `nil`, hiển thị hộp thoại xác nhận đa ngôn ngữ (`EN`/`VI`) thông báo đây là ứng dụng/game Windows cần tải thêm nhân tương thích Wine (~200MB) một lần duy nhất.
     - Khi người dùng bấm **Tải & Chạy ngay (Install & Run)**, mở cửa sổ tiến trình `WineInstallProgressWindowController` hiển thị:
       - Trạng thái hiện tại (Đang tải xuống `X MB / Y MB (Z%)` → Đang giải nén & cấu hình nhân Wine...).
       - Thanh tiến trình `NSProgressIndicator` (determinate khi tải, indeterminate khi giải nén).
       - Nút **Hủy (Cancel)** cho phép dừng tải bất kỳ lúc nào.
   - **Nguồn tải & Quy trình cài đặt tự động (Không cần Homebrew, không cần quyền `sudo`):**
     - Truy vấn GitHub Releases API của `Gcenx/macOS_Wine_builds` để lấy link `.tar.xz` mới nhất, kèm URL dự phòng cố định: `https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-devel-11.21-osx64.tar.xz`.
     - Dùng `URLSession` (`URLSessionDownloadDelegate`) tải về file tạm.
     - Giải nén bằng `/usr/bin/tar -xf <archive.tar.xz> -C ~/Library/Application Support/BugOnExe/Runtime/`.
     - Chạy `/usr/bin/xattr -cr` trên gói `.app` vừa giải nén để gỡ cờ cách ly Gatekeeper.
     - Tự động tiếp tục khởi chạy game ngay sau khi cài đặt hoàn tất.
4. **Khởi chạy Game qua Wine (`WineRunner` tích hợp vào `ProjectorRunner`):**
   - Thiết lập biến môi trường `WINEPREFIX=~/Library/Application Support/BugOnExe/WinePrefix` và `WINEDEBUG=-all`.
   - Đặt `currentDirectoryURL` của tiến trình `Process` đúng bằng thư mục chứa file `.exe` đích (bắt buộc để các game như `Plants Vs Zombies VN Portable.exe` nạp được `main.pak`, `bass.dll`, `properties/`).
   - Khởi chạy tiến trình Wine bất đồng bộ (không khóa luồng giao diện chính) và đảm bảo `AppDelegate` không tự đóng ứng dụng (`NSApp.terminate`) trong lúc đang tải Wine hoặc đang giải nén lần đầu.
5. **Đa ngôn ngữ (`EN` / `VI`) & Kiểm thử tự động:**
   - Bổ sung đầy đủ khóa ngôn ngữ tiếng Anh và tiếng Việt trong `LocalizationManager.swift`, `Resources/en.lproj/Localizable.strings` và `Resources/vi.lproj/Localizable.strings`.
   - Viết bộ unit test kiểm tra: nhận diện 7z SFX + đọc `RunProgram`, giải nén cache 7z SFX bằng `/usr/bin/tar`, định vị Wine binary, và luồng điều phối giữa Flash vs Wine.

### Phi mục tiêu (Non-Goals)
- Không đóng gói sẵn Wine vào trong file `Bug-On-EXE-macOS.dmg` / `.zip` để tránh làm bộ cài tăng từ 18MB lên hàng trăm MB.
- Không yêu cầu người dùng mở Terminal, cài đặt Homebrew hay nhập mật khẩu quản trị viên (`sudo`).

### Điều cần tránh (Anti-Goals)
- Không giải nén gói 7-Zip SFX vào `/tmp` bị hệ điều hành xóa khi khởi động lại làm mất file save của người chơi.
- Không thực thi file `KillDuplicate.cmd` bên trong gói 7z SFX.
- Không làm chậm hoặc ảnh hưởng đến tốc độ mở file Flash `.exe` / `.swf` hiện tại.

---

## 3. Các hướng tiếp cận đã cân nhắc (Approaches)

| Phương án | Mô tả | Đánh đổi (Trade-offs) | Quyết định |
| :--- | :--- | :--- | :--- |
| **Phương án 1: Tải trực tiếp gói `Wine` độc lập (`URLSession`) + Bóc tách sẵn 7z SFX bằng nhân macOS** | Phân loại file `.exe`; nếu là 7z SFX thì cắt phần `7z` và giải nén bằng `/usr/bin/tar` vào thư mục cố định trong `Application Support`, đọc `RunProgram`; nếu thiếu Wine thì tải ngầm gói `wine-osx64.tar.xz` kèm thanh tiến trình và cài vào `Application Support/BugOnExe/Runtime/`. | **Ưu:** Hoạt động trên mọi máy Mac không cần Homebrew hay quyền `sudo`, thanh tiến trình chính xác từng MB, bỏ qua `KillDuplicate.cmd` lỗi, mở lần 2 tức thì và giữ nguyên file save.<br>**Nhược:** Cần viết thêm mô-đun bóc tách SFX và quản lý tải/giải nén Wine trong Swift. | **Đã chọn** |
| **Phương án 2: Tải gói `Wine` độc lập nhưng đưa thẳng file `.exe` gốc cho Wine tự giải nén** | Tải Wine ngầm như Phương án 1 nhưng không bóc tách 7z SFX trên macOS mà để vỏ SFX tự bung vào `%Temp%` của Wine. | **Ưu:** Ít code xử lý 7z SFX hơn.<br>**Nhược:** Dễ treo ở `KillDuplicate.cmd`, mỗi lần mở phải giải nén lại 35MB, thoát game bị `Delete="%%T"` xóa mất dữ liệu tạm. | Loại bỏ |
| **Phương án 3: Gọi ngầm Homebrew (`brew install --cask wine-stable`)** | Dùng lệnh `brew` chạy ngầm để cài Wine. | **Ưu:** Không phải tự quản lý link tải `.tar.xz`.<br>**Nhược:** Máy người dùng phổ thông thường không có Homebrew, không đo được `%` tiến trình tải chính xác, đôi lúc kẹt vì hỏi mật khẩu `sudo`. | Loại bỏ |

---

## 4. Chi tiết quyết định thiết kế (The How)

### 4.1. Cấu trúc Mô-đun Mới & Mở rộng
1. `Sources/Core/PortableExeExtractor.swift`:
   - `enum ExeExecutableKind: Equatable`:
     - `.flash(SwfPayload)`
     - `.sevenZipSfx(archiveOffset: Int, runProgram: String?)`
     - `.standaloneWin32`
   - `static func classify(fileURL: URL) throws -> ExeExecutableKind` và `static func classify(data: Data) throws -> ExeExecutableKind`:
     - Thử `ExeSwfExtractor.extract(from: data)` trước. Nếu thành công → `.flash(payload)`.
     - Kiểm tra 2 byte đầu là `0x4D, 0x5A` (`"MZ"`). Nếu không phải → ném lỗi `.notAValidExecutable`.
     - Tìm chuỗi byte chữ ký 7z `[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]` trong vùng `data`. Nếu tìm thấy tại `offset > 0`:
       - Tìm khối `;!@Install@!UTF-8!` đến `;!@InstallEnd@!` nằm trước `offset` để parse giá trị `RunProgram="..."` (hỗ trợ cả `RunProgram="\"Plants Vs Zombies VN Portable.exe\""` và `RunProgram="\"%%T\\game.exe\""`).
       - Trả về `.sevenZipSfx(archiveOffset: offset, runProgram: parsedProgram)`.
     - Nếu không có chữ ký 7z → trả về `.standaloneWin32`.
   - `final class PortableAppSessionManager`:
     - Quản lý thư mục `~/Library/Application Support/BugOnExe/PortableApps/<hash>-<name>/`.
     - Hàm `preparePortableSession(for fileURL: URL, archiveOffset: Int, runProgram: String?) throws -> URL` trả về đường dẫn tới file `.exe` thực thi bên trong thư mục đã giải nén.
2. `Sources/Core/WineRuntimeManager.swift`:
   - Quản lý thư mục `~/Library/Application Support/BugOnExe/Runtime/` và `~/Library/Application Support/BugOnExe/WinePrefix/`.
   - Hàm `locateWineBinary() -> URL?`: tìm kiếm file thực thi `wine` hoặc `wine64` trong thư mục `Runtime`, `/Applications` hoặc Homebrew.
   - Hàm `downloadAndInstallWine(progressHandler: @escaping (WineInstallProgress) -> Void, completion: @escaping (Result<URL, Error>) -> Void) -> CancellableTask`:
     - Tải gói `.tar.xz`, giải nén bằng `/usr/bin/tar`, gỡ quarantine bằng `/usr/bin/xattr -cr`, kiểm tra lại `locateWineBinary()`.
   - Hàm `launchWindowsExecutable(exeURL: URL, wineBinaryURL: URL, completion: @escaping (Result<Void, Error>) -> Void)`:
     - Khởi chạy `Process` với `executableURL = wineBinaryURL`, `arguments = [exeURL.path]`, `currentDirectoryURL = exeURL.deletingLastPathComponent()`, và biến môi trường `WINEPREFIX`, `WINEDEBUG=-all`.
3. `Sources/App/WineInstallProgressWindowController.swift`:
   - Cửa sổ `NSWindowController` nhỏ gọn (`440×160`), hiển thị tiêu đề, thanh `NSProgressIndicator`, nhãn dung lượng/phần trăm tải và nút Hủy.
4. Cập nhật `Sources/App/ProjectorRunner.swift` & `Sources/App/AppDelegate.swift`:
   - Trong `ProjectorRunner.run(fileURL:completion:)`:
     - Phân loại file bằng `PortableExeExtractor.classify(fileURL:)`.
     - Nếu là `.flash(payload)` → giữ nguyên luồng `SessionManager` + `Flash Player.app`.
     - Nếu là `.sevenZipSfx` hoặc `.standaloneWin32` → kiểm tra `WineRuntimeManager.shared.locateWineBinary()`. Nếu chưa có Wine, hiện `NSAlert` hỏi tải Wine → mở `WineInstallProgressWindowController` tải & cài đặt → giải nén gói 7z SFX (nếu cần) → gọi `launchWindowsExecutable`.
   - Cập nhật `scripts/build_app.sh` để biên dịch thêm các file Swift mới vào binary `BugOnMacExe`.

---

## 5. Phần dành cho Builder quyết định (What's Left to the Builder)
- Chi tiết bố cục UI (font chữ, khoảng cách padding) của cửa sổ tiến trình `WineInstallProgressWindowController`.
- Cách tổ chức class nội bộ cho `URLSessionDownloadDelegate` trong `WineRuntimeManager` để báo cáo tốc độ và phần trăm tải mượt mà trên MainActor/main queue.
- Danh sách từ khóa loại trừ các file `.exe` phụ (như `unins000.exe`) khi quét dự phòng trong thư mục giải nén 7z SFX.
