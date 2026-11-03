<p align="center">
  <img src="Resources/AppIcon-Preview.png" width="160" height="160" alt="Bug On EXE App Icon" />
</p>

<h1 align="center">Bug On EXE</h1>

<p align="center">
  <em>Seamlessly run interactive Adobe Flash (.swf, Flash Projector .exe) and lightweight portable Windows applications on macOS with a single double-click.</em><br/>
  <strong>Mở và chạy mượt mà file Flash (.swf, .exe) cùng ứng dụng Windows portable trên macOS bằng một cú double-click.</strong>
</p>

<p align="center">
  <a href="https://github.com/stark/bug-on-mac-exe/releases"><img src="https://img.shields.io/badge/Platform-macOS_13%2B-blue?logo=apple" alt="macOS 13+" /></a>
  <img src="https://img.shields.io/badge/Architecture-x86__64_%7C_Apple_Silicon_(Rosetta_2)-informational" alt="Architecture" />
  <img src="https://img.shields.io/badge/Vibe_Coded_with-Google_Gemini-8E75C2?logo=google&logoColor=white" alt="Vibe Coded with Google Gemini" />
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" /></a>
</p>

<p align="center">
  <strong>Language:</strong> <a href="#-english">🇺🇸 English</a> | <a href="#-tiếng-việt">🇻🇳 Tiếng Việt</a>
</p>

---

## 🇺🇸 English

### 🐞 The Story Behind "Bug On EXE" & Vibe Coding with Gemini

**Bug On EXE** was brought to life through the creative process of **Vibe coding with Google Gemini**. The project embraces the harmony between human intent and AI agility—transforming an ambitious idea into a production-grade, highly polished macOS native utility with modern aesthetics and robust engineering.

The name carries a witty double meaning:
- In Vietnamese phonetics, **"Bug On"** sounds identical to **"Bất Ổn"** (meaning *turbulent*, *chaotic*, or *sketchy*). Opening and running Windows `.exe` binaries directly on a Mac has historically felt like a chaotic and "bất ổn" experience.
- In software terminology, it represents hunting **bugs** while flipping the switch **ON**—delivering immediate execution so seamlessly that Windows `.exe` files behave like first-class macOS citizens.

---

### ⚙️ Dual-Engine Architecture: How It Works

**Bug On EXE** implements an intelligent two-tier execution pipeline that automatically routes incoming files to the optimal execution engine without requiring any user intervention:

```
                  ┌───────────────────────────────┐
                  │   User double-clicks .exe    │
                  └───────────────┬───────────────┘
                                  │
                                  ▼
                ┌───────────────────────────────────┐
                │   PE Header & Signature Scanner   │
                └─────────┬───────────────────────┬─┘
                          │                       │
      Embedded Flash/SWF  │                       │ Non-Flash / Portable EXE
       Signature Detected │                       │
                          ▼                       ▼
            ┌───────────────────────────┐   ┌───────────────────────────┐
            │   Engine 1: Flash Engine  │   │    Engine 2: Wine Engine  │
            ├───────────────────────────┤   ├───────────────────────────┤
            │ • Instant payload extract │   │ • 7-Zip SFX unpacker      │
            │ • Auto-generate FlashTrust│   │ • Wine 9+ 64-bit runtime  │
            │ • Direct Projector launch │   │ • Persistent sessions     │
            └───────────────────────────┘   └───────────────────────────┘
```

1. **Engine 1 — Native Flash Projector (Sub-second Launch):**
   - **Deep Payload Extraction:** Inspects PE32 binaries for embedded ActionScript 2 / 3 and Adobe Flex payloads (matching the classic `0xFA123456` Flash Projector trailer as well as nested resource boundaries).
   - **Zero Sandbox Friction:** Automatically generates and registers security trust entries in `FlashPlayerTrust`, eliminating legacy Flash security prompts and linking companion media/XML assets located in the same directory.
   - **Native 64-bit Projector:** Launches directly via a bundled 64-bit Adobe Flash Player Projector runtime on macOS.

2. **Engine 2 — Portable Windows Executable & 7-Zip SFX Engine:**
   - **Portable Archive Extraction:** Detects and unpacks 7-Zip Self-Extracting (`.sfx`) executables into sandboxed temporary working spaces.
   - **Automated Wine Dispatch:** When an `.exe` is not a Flash Projector, the app dynamically routes execution to Wine runtime management with persistent session state, enabling lightweight Windows tools and legacy utilities to run without complex VM setups.

---

### ✨ Key Features

- **Double-Click Association:** One-click registration as the default macOS handler for both `.exe` and `.swf` files via Finder.
- **macOS 26+ Liquid Glass Interface:** Built with SwiftUI utilizing native `.ultraThinMaterial`, translucent glass cards, specular rim highlights, and dynamic system vibrancy.
- **Smooth Backward Fallback:** Automatically detects the host OS version; on macOS < 26, it gracefully falls back to a clean, lightweight AppKit view for guaranteed stability.
- **Library & Recents Manager:** Manage frequently opened utilities, pin important apps, search on the fly, or drag-and-drop new files into the launcher dropzone.
- **Adaptive Mascot App Icon:** Brand icon featuring the cute orange robot bug riding an `.EXE` rocket with exhaust flames. Built with Xcode 26 Asset Catalog to dynamically adapt between Light mode (ceramic off-white) and Dark mode (obsidian metallic).
- **Instant Bilingual Switcher:** Complete runtime interface localization in English and Vietnamese.

---

### 🧱 Standardized Tech Stack

| Layer | Technologies & Standards | Purpose |
| :--- | :--- | :--- |
| **Language & Toolchain** | Swift 5.10+, Clang, Xcode Command Line Tools | Fast native compiled performance without heavy dependencies |
| **User Interface** | SwiftUI, AppKit, `NSHostingController` | Liquid Glassmorphic card grid on macOS 26+, classic fallback on macOS < 26 |
| **Asset & Icon Pipeline** | WebKit CoreGraphics, `actool`, `iconutil` | High-fidelity vector SVG rasterization with full filter and dual-appearance support |
| **Flash Runtime** | Adobe Flash Player Projector 32 (Mach-O 64-bit `x86_64`) | Direct, sandbox-free Flash execution |
| **Windows Emulation** | Wine 9.0+, 7-Zip Portable SFX Extractor | Compatibility layer for general portable Windows `.exe` files |
| **Packaging & Release** | Bash, `hdiutil` (UDZO DMG), ad-hoc codesign | Self-contained, zero-configuration `.dmg` and `.zip` distribution |

---

### 🚀 Installation & Quick Start

#### Option 1: Download Pre-built Release (Recommended)

1. Navigate to the [**Releases**](../../releases) section on GitHub.
2. Download the latest release:
   - **`Bug-On-EXE-macOS.dmg`** *(Recommended)*: Open the DMG and drag **Bug On EXE.app** into your **Applications** folder.
   - **`Bug-On-EXE-macOS.zip`**: Extract and copy **Bug On EXE.app** to `/Applications`.
3. **Bypassing macOS Gatekeeper (First Launch):**  
   Because this application is distributed independently without a paid Apple Developer certificate, macOS Gatekeeper may display an *"unidentified developer"* notice. To clear quarantine, simply run this one-line command in your **Terminal**:
   ```bash
   xattr -cr "/Applications/Bug On EXE.app"
   ```
   *(Alternatively, right-click the app in Finder and select **Open**).*
4. Launch **Bug On EXE**, click **Set as Default**, and enjoy running your `.exe` and `.swf` files natively!

---

### 🛠️ Building from Source

**Requirements:**
- macOS 13.0 or later (Intel `x86_64` or Apple Silicon via Rosetta 2)
- Xcode Command Line Tools or Xcode 16+ (`swiftc`, `actool`, `iconutil`)

```bash
# Clone the repository
git clone https://github.com/stark/bug-on-mac-exe.git
cd bug-on-mac-exe

# 1. Build and install directly into /Applications/Bug On EXE.app
bash scripts/build_app.sh

# 2. Package release DMG and ZIP into dist/
bash scripts/package_release.sh
```

---

## 🇻🇳 Tiếng Việt

*(Nội dung tiếng Việt sẽ được hoàn thiện ở Task 2)*
