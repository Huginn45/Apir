# Apir (Adaptive Presentation Interface & Remote) — QR Pairing Edition

A cross-platform wireless presentation clicker, glowing dot-matrix trackpad, click-through Crimson Laser & Spotlight Beam overlays, live slide thumbnail viewer, and remote keyboard/voice dictation controller over local Wi-Fi.

## Official Cultural Brand Identity

- **Color Palette:**
  - **Deep Maroon (`#561217`):** Primary scaffold & background
  - **Golden Amber (`#F59E1D`):** Primary accent & trackpad touch glow
  - **Warm Cream (`#FDECC8` / 25% opacity):** High-contrast text & inactive dot-matrix grid
  - **Crimson Red (`#9E1F36`):** Active Virtual Laser Pointer glow
  - **Royal Blue (`#2B62A7`):** Connected tech status & network accent
- **Typography:** `Tribo` for headers/wordmark (`"APIR"`) and `Garet` for body/buttons (fallback to `Montserrat` / `Plus Jakarta Sans`).
- **Official Emblem:** High-Five cultural weave logo (`apir_desktop/assets/apir_logo.png`, `apir_desktop/assets/apir_logo.ico`, `apir_mobile/assets/images/apir_logo.png`).

## Monorepo Structure

- [`ApirDesktop.exe`](./ApirDesktop.exe) — Standalone, windowless Windows executable with system tray support.
- [`/apir_desktop`](./apir_desktop) — Python hybrid HTTP + WebSocket companion daemon (`websockets`, `pynput`, `qrcode`, `pillow`, `pystray`, `zeroconf`, `mss`, `tkinter`).
  - [`server.py`](./apir_desktop/server.py): Detects active LAN IPv4 interfaces, displays the Cultural-Brand QR Pairing window on the main thread with network adapter switching and 1-click PIN rotation (`↻ New PIN`), advertises `_apir._tcp.local.` via mDNS/Bonjour, and executes Per-Monitor DPI-aware mouse, slide, presentation (`F5`/`B`/`Esc`), volume, text/dictation, click-through Crimson Laser & Spotlight overlays, live slide preview streaming, and Do Not Disturb commands.
  - [`mobile_web_ui.py`](./apir_desktop/mobile_web_ui.py): Embedded Zero-Install PWA Mobile Web Controller served directly by `server.py` on port `8765` with automatic background reconnection.
  - [`test_client.py`](./apir_desktop/test_client.py): End-to-end automated verification client.
- [`/apir_mobile`](./apir_mobile) — Native Flutter (`com.apir.remote`) Android/iOS wireless controller.
  - [`lib/screens/scanner_screen.dart`](./apir_mobile/lib/screens/scanner_screen.dart): Deep Maroon QR viewfinder with Golden Amber glowing rounded-square overlay, 1-tap `shared_preferences` host reconnection, and Manual IP Entry bottom sheet.
  - [`lib/screens/controller_screen.dart`](./apir_mobile/lib/screens/controller_screen.dart): Deep Maroon presenter controller with interactive `CustomPainter` dot-matrix trackpad (Golden Amber cursor glow / Crimson Red laser glow), Spotlight Beam, Live Slide View, Presentation Countdown Timer with haptic alerts, `<` / `>` slide buttons (plus hardware volume key navigation), Volume & Presentation (`F5` / `Blackout` / `Esc`) popover, Do Not Disturb toggle, Presenter Lock, automatic reconnection, and real-time Remote Keyboard & Voice Dictation.

## Quick Start

### 1. Start the Desktop Server
Double-click [`ApirDesktop.exe`](./ApirDesktop.exe) (or [`start_apir_desktop.bat`](./start_apir_desktop.bat)), or run from source:
```powershell
cd apir_desktop
.\.venv\Scripts\python.exe server.py
```

### 2. Run the End-to-End Verification Client
```powershell
cd apir_desktop
.\.venv\Scripts\python.exe test_client.py --uri ws://127.0.0.1:8765 --token <4_DIGIT_PIN>
```

### 3. Run the Mobile Flutter App
```bash
cd apir_mobile
flutter pub get
flutter run
```
