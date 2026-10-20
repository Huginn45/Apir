# Apir (Adaptive Presentation Interface & Remote) — QR Pairing Edition

A cross-platform wireless presentation clicker, glowing dot-matrix trackpad, virtual crimson laser pointer, and remote keyboard/voice dictation controller over local Wi-Fi.

## Monorepo Structure

- [`/apir_desktop`](./apir_desktop) — Python WebSocket companion daemon (`websockets`, `pynput`, `qrcode`, `pillow`, `tkinter`).
  - [`server.py`](./apir_desktop/server.py): Detects active LAN IPv4, displays the QR code in both the terminal and a minimal OLED `tkinter` popup window, verifies the 4-digit PIN handshake, and executes low-latency OS mouse, slide, volume, text/dictation, click-through laser overlay, and Do Not Disturb commands.
  - [`test_client.py`](./apir_desktop/test_client.py): End-to-end automated verification client.
- [`/apir_mobile`](./apir_mobile) — Flutter (`com.apir.remote`) Android/iOS wireless controller.
  - [`lib/screens/scanner_screen.dart`](./apir_mobile/lib/screens/scanner_screen.dart): Dark-mode `mobile_scanner` QR viewfinder with glowing electric-blue rounded square overlay, 1-tap `shared_preferences` host reconnection, and Manual IP Entry modal.
  - [`lib/screens/controller_screen.dart`](./apir_mobile/lib/screens/controller_screen.dart): Pitch-black (`#000000`) OLED presenter controller with interactive `CustomPainter` dot-matrix trackpad (electric blue cursor glow / crimson red laser glow), `<` / `>` slide buttons, Laser toggle/hold, Volume popover, Do Not Disturb toggle, Presenter Lock, and real-time Remote Keyboard & Voice Dictation.

## Quick Start

### 1. Start the Desktop Server
Double-click [`start_apir_desktop.bat`](./start_apir_desktop.bat) or run:
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
