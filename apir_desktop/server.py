#!/usr/bin/env python3
"""
Apir Desktop Companion Server (Adaptive Presentation Interface & Remote)
------------------------------------------------------------------------
Full-featured desktop companion daemon with:
- Cultural Brand Identity UI (Deep Maroon `#561217`, Golden Amber `#F59E1D`,
  Warm Cream `#FDECC8`, Crimson Red `#9E1F36`, Royal Blue `#2B62A7`)
- Main-Thread Tkinter GUI (100% responsive on Windows) + Background Asyncio Server
- Single-Instance Handover (`/show-qr` brings existing instance to front instead of Errno 10048)
- Multi-Interface Network Switcher (Ethernet / Wi-Fi / Mobile Hotspot / VPN)
- mDNS / Bonjour (`zeroconf`) `_apir._tcp.local.` Service Advertisement
- Low-latency `pynput` Mouse, Slide, Scroll, Volume, Keyboard/Dictation & Presentation Keys
- Click-through Crimson Red Laser Pointer & Fullscreen Spotlight Beam Overlays
- Live Slide / Desktop Screen Thumbnail Streaming (`mss` / `ImageGrab`)
- Zero-install PWA Mobile Web Controller (`mobile_web_ui.py`)
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import ctypes
import io
import json
import logging
import os
from pathlib import Path
import platform
import queue
import random
import socket
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Set, Tuple

import qrcode
from PIL import Image, ImageGrab, ImageTk
from pynput.keyboard import Controller as KeyboardController, Key
from pynput.mouse import Button, Controller as MouseController
import websockets
from websockets.asyncio.server import ServerConnection, serve
from websockets.datastructures import Headers
from websockets.http11 import Request, Response

from mobile_web_ui import PWA_MANIFEST_JSON, render_mobile_web_html

try:
    import tkinter as tk
    TKINTER_AVAILABLE = True
except Exception:
    TKINTER_AVAILABLE = False

try:
    import ifaddr
    IFADDR_AVAILABLE = True
except Exception:
    IFADDR_AVAILABLE = False

try:
    import pystray
    PYSTRAY_AVAILABLE = True
except Exception:
    PYSTRAY_AVAILABLE = False

try:
    from zeroconf import ServiceInfo, Zeroconf
    ZEROCONF_AVAILABLE = True
except Exception:
    ZEROCONF_AVAILABLE = False

try:
    import mss
    MSS_AVAILABLE = True
except Exception:
    MSS_AVAILABLE = False

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("apir.desktop")


def get_resource_path(relative_path: str) -> Path:
    """Resolve asset paths both in normal source execution and PyInstaller bundles."""
    base_path = getattr(sys, "_MEIPASS", None)
    if base_path:
        return Path(base_path) / relative_path
    return Path(__file__).resolve().parent / relative_path


# Official Apir Cultural Brand Palette & Logo Path
BRAND_DEEP_MAROON = "#561217"
BRAND_GOLDEN_AMBER = "#F59E1D"
BRAND_WARM_CREAM = "#FDECC8"
BRAND_WARM_CREAM_25_ON_MAROON = "#80483B"
BRAND_CRIMSON_RED = "#9E1F36"
BRAND_ROYAL_BLUE = "#2B62A7"
LOGO_PATH = get_resource_path("assets/apir_logo.png")


def ensure_single_instance_or_focus(port: int) -> bool:
    """
    Check if an Apir Desktop instance is already listening on `port`.
    - If a healthy instance is already running, send `GET /show-qr` so its QR
      window pops to the front of the user's screen, and return `False` so this
      duplicate process exits cleanly without throwing `[WinError 10048]`.
    - If port `port` is free, return `True`.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.4)
        in_use = sock.connect_ex(("127.0.0.1", port)) == 0

    if not in_use:
        return True

    # Port is in use: ask the existing instance to bring its QR window to front
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/show-qr", timeout=1.2) as resp:
            if resp.status == 200:
                logger.info("Existing Apir instance focused via /show-qr.")
                return False
    except Exception:
        pass

    return False


def get_local_lan_ip() -> str:
    """Detect the laptop's primary active local LAN IPv4 address (avoiding 127.0.0.1)."""
    probe_targets = [("8.8.8.8", 80), ("1.1.1.1", 80), ("10.255.255.255", 1)]
    for host, port in probe_targets:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.settimeout(0.5)
                s.connect((host, port))
                ip = s.getsockname()[0]
                if ip and not ip.startswith("127."):
                    return ip
        except OSError:
            continue

    try:
        hostname = socket.gethostname()
        for addr_info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = addr_info[4][0]
            if ip and not ip.startswith("127.") and not ip.startswith("169.254."):
                return ip
    except OSError:
        pass

    return "127.0.0.1"


def list_all_lan_interfaces() -> List[Tuple[str, str]]:
    """
    Return a list of `(label, ipv4)` tuples for all active non-loopback network
    interfaces (e.g. Ethernet, Wi-Fi, Windows Mobile Hotspot, VPN), with the
    primary LAN route listed first.
    """
    primary_ip = get_local_lan_ip()
    found: List[Tuple[str, str]] = []
    seen_ips: Set[str] = set()

    if IFADDR_AVAILABLE:
        try:
            for adapter in ifaddr.get_adapters():
                nice = getattr(adapter, "nice_name", adapter.name) or "LAN"
                for ip_obj in adapter.ips:
                    if isinstance(ip_obj.ip, str):
                        ip_str = ip_obj.ip
                        if (
                            not ip_str.startswith("127.")
                            and not ip_str.startswith("169.254.")
                            and ip_str not in seen_ips
                        ):
                            seen_ips.add(ip_str)
                            found.append((nice[:22], ip_str))
        except Exception:
            pass

    if primary_ip not in seen_ips:
        found.insert(0, ("Primary LAN", primary_ip))
    else:
        found.sort(key=lambda item: 0 if item[1] == primary_ip else 1)

    return found or [("Localhost", "127.0.0.1")]


def generate_session_pin(fixed_pin: Optional[str] = None) -> str:
    """Generate a 4-digit session PIN for the Apir QR Handshake."""
    if fixed_pin and len(fixed_pin) == 4 and fixed_pin.isdigit():
        return fixed_pin
    return f"{random.randint(0, 9999):04d}"


def build_pairing_payload(ip: str, port: int, hostname: str, token: str) -> Dict[str, str]:
    """Create the canonical Apir QR pairing JSON payload."""
    return {
        "app": "apir",
        "uri": f"ws://{ip}:{port}",
        "host": hostname,
        "token": token,
    }


def build_pairing_url(payload: Dict[str, str], ip: str, port: int) -> str:
    """Build a universal HTTP+QR pairing URL."""
    qs = urllib.parse.urlencode(payload)
    return f"http://{ip}:{port}/?{qs}"


def render_qr_ascii(payload_json: str) -> str:
    """Render the QR code for terminal output."""
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=1,
        border=2,
    )
    qr.add_data(payload_json)
    qr.make(fit=True)

    if platform.system() == "Windows":
        matrix = qr.get_matrix()
        lines = []
        for row in matrix:
            lines.append("".join("  " if cell else "##" for cell in row))
        return "\n".join(lines)

    buf = io.StringIO()
    qr.print_ascii(out=buf, invert=True)
    return buf.getvalue()


def generate_qr_pil_image(payload_json: str, size: int = 280) -> Image.Image:
    """
    Generate a high-contrast cultural-brand PIL Image of the QR code
    (Deep Maroon `#561217` modules on Warm Cream `#FDECC8` card background).
    """
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=10,
        border=3,
    )
    qr.add_data(payload_json)
    qr.make(fit=True)
    img = qr.make_image(
        fill_color=BRAND_DEEP_MAROON,
        back_color=BRAND_WARM_CREAM,
    ).convert("RGB")
    return img.resize((size, size), Image.Resampling.NEAREST)


def capture_screen_thumbnail_base64(max_width: int = 480) -> Optional[str]:
    """Capture a lightweight JPEG thumbnail of the primary screen for live slide preview."""
    try:
        pil_shot: Optional[Image.Image] = None
        if MSS_AVAILABLE:
            with mss.mss() as sct:
                mon = sct.monitors[1] if len(sct.monitors) > 1 else sct.monitors[0]
                raw = sct.grab(mon)
                pil_shot = Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")
        else:
            pil_shot = ImageGrab.grab().convert("RGB")

        if pil_shot is None:
            return None

        w, h = pil_shot.size
        if w > max_width:
            new_h = max(1, int(h * (max_width / float(w))))
            pil_shot = pil_shot.resize((max_width, new_h), Image.Resampling.BILINEAR)

        buf = io.BytesIO()
        pil_shot.save(buf, format="JPEG", quality=55, optimize=True)
        return base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception as exc:
        logger.debug("Screen preview capture skipped: %s", exc)
        return None


class ApirOverlayUI:
    """
    Manages:
    1. The Cultural-Brand Tkinter QR Pairing Popup window (running on the Main Thread!).
    2. The topmost, transparent, click-through Virtual Laser Pointer overlay window.
    3. The topmost, click-through Fullscreen Spotlight Beam overlay window.
    4. The Windows/macOS System Tray icon (`pystray`).
    """

    def __init__(
        self,
        interfaces: List[Tuple[str, str]],
        port: int,
        hostname: str,
        token: str,
        headless: bool = False,
    ) -> None:
        self.interfaces = interfaces
        self.active_iface_idx = 0
        self.port = port
        self.hostname = hostname
        self.token = token
        self.headless = headless or not TKINTER_AVAILABLE

        self.cmd_queue: "queue.Queue[Dict[str, Any]]" = queue.Queue()
        self._tray_icon: Optional[Any] = None
        self._root: Optional[tk.Tk] = None
        self._qr_window: Optional[tk.Tk] = None
        self._laser_window: Optional[tk.Toplevel] = None
        self._spotlight_window: Optional[tk.Toplevel] = None
        self._spotlight_canvas: Optional[tk.Canvas] = None
        self._qr_photo: Optional[ImageTk.PhotoImage] = None
        self._logo_photo: Optional[ImageTk.PhotoImage] = None
        self._icon_photo: Optional[ImageTk.PhotoImage] = None
        self._qr_label: Optional[tk.Label] = None
        self._host_label: Optional[tk.Label] = None
        self._iface_btn: Optional[tk.Button] = None

        self._laser_active: bool = False
        self._spotlight_active: bool = False
        self._laser_radius: int = 22
        self._spotlight_radius: int = 135

    @property
    def current_ip(self) -> str:
        return self.interfaces[self.active_iface_idx][1]

    @property
    def current_iface_name(self) -> str:
        return self.interfaces[self.active_iface_idx][0]

    @property
    def payload(self) -> Dict[str, str]:
        return build_pairing_payload(self.current_ip, self.port, self.hostname, self.token)

    @property
    def qr_content(self) -> str:
        return build_pairing_url(self.payload, self.current_ip, self.port)

    def run_main_loop(self) -> None:
        """Run the Tkinter GUI loop directly on the Main Thread so Windows never marks it Not Responding."""
        if self.headless:
            return
        self._start_system_tray()
        self._run_tk_loop()

    def _start_system_tray(self) -> None:
        if not PYSTRAY_AVAILABLE or not LOGO_PATH.exists():
            return
        try:
            tray_img = Image.open(LOGO_PATH).convert("RGB").resize((64, 64), Image.Resampling.LANCZOS)
            menu = pystray.Menu(
                pystray.MenuItem("Show Pairing QR Code", lambda icon, item: self.show_qr_popup(), default=True),
                pystray.MenuItem("Hide Pairing QR Code", lambda icon, item: self.close_qr_popup()),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Quit Apir Server", lambda icon, item: self._quit_all()),
            )
            self._tray_icon = pystray.Icon("Apir", tray_img, "Apir Presentation Companion", menu)
            threading.Thread(target=self._tray_icon.run, name="ApirTrayThread", daemon=True).start()
        except Exception as exc:
            logger.debug("System tray icon skipped: %s", exc)

    def _quit_all(self) -> None:
        try:
            if self._tray_icon:
                self._tray_icon.stop()
        except Exception:
            pass
        self.stop()
        os._exit(0)

    def close_qr_popup(self) -> None:
        if not self.headless:
            self.cmd_queue.put({"action": "close_qr"})

    def show_qr_popup(self) -> None:
        if not self.headless:
            self.cmd_queue.put({"action": "show_qr"})

    def set_laser(self, active: bool, x: int, y: int) -> None:
        if not self.headless:
            self.cmd_queue.put({"action": "laser", "active": active, "x": x, "y": y})

    def set_spotlight(self, active: bool, x: int, y: int) -> None:
        if not self.headless:
            self.cmd_queue.put({"action": "spotlight", "active": active, "x": x, "y": y})

    def stop(self) -> None:
        if not self.headless:
            self.cmd_queue.put({"action": "stop"})

    def _run_tk_loop(self) -> None:
        try:
            self._root = tk.Tk()
            self._create_qr_popup()
            self._create_laser_overlay()
            self._create_spotlight_overlay()

            self._root.after(16, self._poll_queue)
            self._root.mainloop()
        except Exception as exc:
            logger.warning("Tkinter UI loop exited: %s", exc)

    def _cycle_interface(self) -> None:
        if len(self.interfaces) <= 1:
            return
        self.active_iface_idx = (self.active_iface_idx + 1) % len(self.interfaces)
        pil_img = generate_qr_pil_image(self.qr_content, size=240)
        self._qr_photo = ImageTk.PhotoImage(pil_img)
        if self._qr_label is not None:
            self._qr_label.configure(image=self._qr_photo)
        if self._host_label is not None:
            self._host_label.configure(
                text=f"{self.hostname}  •  {self.payload['uri']}"
            )
        if self._iface_btn is not None:
            self._iface_btn.configure(
                text=f"⇄ Network: {self.current_iface_name} ({self.current_ip})"
            )

    def _create_qr_popup(self) -> None:
        if self._root is None:
            return

        win = self._root
        for child in win.winfo_children():
            if child not in (self._laser_window, self._spotlight_window):
                child.destroy()

        win.title("Apir — High-Five Pairing")
        win.configure(bg=BRAND_DEEP_MAROON)
        win.resizable(False, False)
        win.attributes("-topmost", True)

        # Clicking X cleanly exits the application so the user never gets stuck processes
        win.protocol("WM_DELETE_WINDOW", self._quit_all)

        # Center window on screen
        win_w, win_h = 385, 585
        scr_w = win.winfo_screenwidth()
        scr_h = win.winfo_screenheight()
        pos_x = max(0, (scr_w - win_w) // 2)
        pos_y = max(0, (scr_h - win_h) // 2)
        win.geometry(f"{win_w}x{win_h}+{pos_x}+{pos_y}")

        # Official Apir High-Five Logo Badge & Window Icon
        if LOGO_PATH.exists():
            try:
                raw_logo = Image.open(LOGO_PATH).convert("RGB")
                icon_img = raw_logo.resize((64, 64), Image.Resampling.LANCZOS)
                self._icon_photo = ImageTk.PhotoImage(icon_img)
                win.iconphoto(True, self._icon_photo)

                badge_img = raw_logo.resize((64, 64), Image.Resampling.LANCZOS)
                self._logo_photo = ImageTk.PhotoImage(badge_img)

                logo_border = tk.Frame(win, bg=BRAND_GOLDEN_AMBER, padx=2, pady=2)
                logo_border.pack(pady=(12, 4))
                logo_lbl = tk.Label(logo_border, image=self._logo_photo, bg=BRAND_DEEP_MAROON, bd=0)
                logo_lbl.pack()
            except Exception as exc:
                logger.debug("Could not load logo into Tkinter window: %s", exc)

        # Header ("APIR" in Tribo / Golden Amber #F59E1D)
        lbl_title = tk.Label(
            win,
            text="APIR",
            font=("Tribo", 22, "bold"),
            fg=BRAND_GOLDEN_AMBER,
            bg=BRAND_DEEP_MAROON,
        )
        lbl_title.pack(pady=(2, 2))

        lbl_sub = tk.Label(
            win,
            text="Scan with Phone Camera or Apir App to Pair",
            font=("Garet", 10),
            fg=BRAND_WARM_CREAM,
            bg=BRAND_DEEP_MAROON,
        )
        lbl_sub.pack(pady=(0, 8))

        # QR Card Frame with Golden Amber (#F59E1D) primary accent border
        qr_border = tk.Frame(win, bg=BRAND_GOLDEN_AMBER, padx=3, pady=3)
        qr_border.pack()

        qr_inner = tk.Frame(qr_border, bg=BRAND_WARM_CREAM, padx=8, pady=8)
        qr_inner.pack()

        pil_img = generate_qr_pil_image(self.qr_content, size=240)
        self._qr_photo = ImageTk.PhotoImage(pil_img)

        self._qr_label = tk.Label(qr_inner, image=self._qr_photo, bg=BRAND_WARM_CREAM, bd=0)
        self._qr_label.pack()

        # Host & PIN Metadata (Royal Blue #2B62A7 tech status pill + Golden Amber PIN)
        meta_frame = tk.Frame(win, bg=BRAND_DEEP_MAROON)
        meta_frame.pack(pady=(10, 4))

        tech_pill = tk.Frame(
            meta_frame,
            bg=BRAND_ROYAL_BLUE,
            padx=10,
            pady=3,
        )
        tech_pill.pack()

        self._host_label = tk.Label(
            tech_pill,
            text=f"{self.hostname}  •  {self.payload['uri']}",
            font=("Garet", 9, "bold"),
            fg=BRAND_WARM_CREAM,
            bg=BRAND_ROYAL_BLUE,
        )
        self._host_label.pack()

        lbl_pin = tk.Label(
            meta_frame,
            text=f"PIN: {self.token}",
            font=("Garet", 13, "bold"),
            fg=BRAND_GOLDEN_AMBER,
            bg=BRAND_DEEP_MAROON,
        )
        lbl_pin.pack(pady=(5, 4))

        # Action Buttons Row: Switch Network IP & Hide to Tray
        btn_row = tk.Frame(meta_frame, bg=BRAND_DEEP_MAROON)
        btn_row.pack(pady=(2, 0))

        self._iface_btn = tk.Button(
            btn_row,
            text=f"⇄ {self.current_iface_name} ({self.current_ip})",
            command=self._cycle_interface,
            font=("Garet", 8, "bold"),
            fg=BRAND_WARM_CREAM,
            bg=BRAND_WARM_CREAM_25_ON_MAROON,
            activebackground=BRAND_GOLDEN_AMBER,
            activeforeground=BRAND_DEEP_MAROON,
            relief=tk.FLAT,
            padx=8,
            pady=3,
            cursor="hand2",
        )
        self._iface_btn.pack(side=tk.LEFT, padx=4)

        hide_btn = tk.Button(
            btn_row,
            text="Minimize to Tray",
            command=self.close_qr_popup,
            font=("Garet", 8, "bold"),
            fg=BRAND_DEEP_MAROON,
            bg=BRAND_GOLDEN_AMBER,
            activebackground=BRAND_WARM_CREAM,
            activeforeground=BRAND_DEEP_MAROON,
            relief=tk.FLAT,
            padx=8,
            pady=3,
            cursor="hand2",
        )
        hide_btn.pack(side=tk.LEFT, padx=4)

        win.update_idletasks()
        win.deiconify()
        win.lift()
        win.attributes("-topmost", True)
        win.focus_force()

        if platform.system() == "Windows":
            try:
                hwnd = ctypes.windll.user32.GetParent(win.winfo_id()) or win.winfo_id()
                ctypes.windll.user32.ShowWindow(hwnd, 1)
                ctypes.windll.user32.ShowWindow(hwnd, 5)
                ctypes.windll.user32.SetForegroundWindow(hwnd)
            except Exception:
                pass

        self._qr_window = win

    def _apply_click_through(self, win: tk.Toplevel, transparent_key: str, alpha: float = 1.0) -> None:
        if platform.system() == "Windows":
            win.attributes("-transparentcolor", transparent_key)
            if alpha < 1.0:
                win.attributes("-alpha", alpha)
            win.update_idletasks()
            try:
                hwnd = ctypes.windll.user32.GetParent(win.winfo_id()) or win.winfo_id()
                GWL_EXSTYLE = -20
                WS_EX_LAYERED = 0x00080000
                WS_EX_TRANSPARENT = 0x00000020
                WS_EX_TOOLWINDOW = 0x00000080
                ex_style = ctypes.windll.user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
                ctypes.windll.user32.SetWindowLongW(
                    hwnd,
                    GWL_EXSTYLE,
                    ex_style | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW,
                )
            except Exception as exc:
                logger.debug("Could not apply WS_EX_TRANSPARENT: %s", exc)

    def _create_laser_overlay(self) -> None:
        if self._root is None:
            return

        win = tk.Toplevel(self._root)
        win.withdraw()
        win.overrideredirect(True)
        win.attributes("-topmost", True)

        transparent_key = "#010101"
        win.configure(bg=transparent_key)

        size = self._laser_radius * 2 + 8
        canvas = tk.Canvas(
            win,
            width=size,
            height=size,
            bg=transparent_key,
            highlightthickness=0,
            bd=0,
        )
        canvas.pack()

        cx = size // 2
        cy = size // 2
        r_outer = self._laser_radius
        r_mid = int(self._laser_radius * 0.65)
        r_core = int(self._laser_radius * 0.32)

        canvas.create_oval(
            cx - r_outer, cy - r_outer, cx + r_outer, cy + r_outer,
            outline=BRAND_CRIMSON_RED, width=2, fill=""
        )
        canvas.create_oval(
            cx - r_mid, cy - r_mid, cx + r_mid, cy + r_mid,
            outline=BRAND_GOLDEN_AMBER, width=2, fill=BRAND_CRIMSON_RED
        )
        canvas.create_oval(
            cx - r_core, cy - r_core, cx + r_core, cy + r_core,
            outline=BRAND_WARM_CREAM, width=1, fill=BRAND_WARM_CREAM
        )

        self._apply_click_through(win, transparent_key)
        self._laser_window = win

    def _create_spotlight_overlay(self) -> None:
        if self._root is None:
            return

        win = tk.Toplevel(self._root)
        win.withdraw()
        win.overrideredirect(True)
        win.attributes("-topmost", True)

        scr_w = win.winfo_screenwidth()
        scr_h = win.winfo_screenheight()
        win.geometry(f"{scr_w}x{scr_h}+0+0")

        transparent_key = "#010203"
        canvas = tk.Canvas(
            win,
            width=scr_w,
            height=scr_h,
            bg="#080405",
            highlightthickness=0,
            bd=0,
        )
        canvas.pack(fill=tk.BOTH, expand=True)

        self._apply_click_through(win, transparent_key, alpha=0.68)
        self._spotlight_window = win
        self._spotlight_canvas = canvas

    def _poll_queue(self) -> None:
        if self._root is None:
            return
        try:
            while True:
                cmd = self.cmd_queue.get_nowait()
                action = cmd.get("action")

                if action == "close_qr":
                    if self._qr_window is not None:
                        try:
                            self._qr_window.withdraw()
                        except Exception:
                            pass

                elif action == "show_qr":
                    if self._qr_window is not None:
                        self._qr_window.deiconify()
                        self._qr_window.lift()
                        self._qr_window.focus_force()

                elif action == "laser":
                    active = bool(cmd.get("active", False))
                    x = int(cmd.get("x", 0))
                    y = int(cmd.get("y", 0))
                    self._update_laser_window(active, x, y)

                elif action == "spotlight":
                    active = bool(cmd.get("active", False))
                    x = int(cmd.get("x", 0))
                    y = int(cmd.get("y", 0))
                    self._update_spotlight_window(active, x, y)

                elif action == "stop":
                    self._root.quit()
                    return
        except queue.Empty:
            pass

        self._root.after(12, self._poll_queue)

    def _update_laser_window(self, active: bool, x: int, y: int) -> None:
        if self._laser_window is None:
            return
        size = self._laser_radius * 2 + 8
        offset = size // 2
        if active:
            self._laser_window.geometry(f"{size}x{size}+{x - offset}+{y - offset}")
            if not self._laser_active:
                self._laser_window.deiconify()
                self._laser_window.lift()
                self._laser_active = True
        else:
            if self._laser_active:
                self._laser_window.withdraw()
                self._laser_active = False

    def _update_spotlight_window(self, active: bool, x: int, y: int) -> None:
        if self._spotlight_window is None or self._spotlight_canvas is None:
            return
        if active:
            r = self._spotlight_radius
            self._spotlight_canvas.delete("spot")
            self._spotlight_canvas.create_oval(
                x - r, y - r, x + r, y + r,
                fill="#010203",
                outline=BRAND_GOLDEN_AMBER,
                width=3,
                tags="spot",
            )
            if not self._spotlight_active:
                self._spotlight_window.deiconify()
                self._spotlight_window.lift()
                self._spotlight_active = True
        else:
            if self._spotlight_active:
                self._spotlight_window.withdraw()
                self._spotlight_active = False


class OSInputExecutor:
    """
    Executes low-latency mouse, keyboard, media, laser, spotlight, and DND operations.
    """

    def __init__(self, ui: ApirOverlayUI) -> None:
        self.mouse = MouseController()
        self.keyboard = KeyboardController()
        self.ui = ui
        self.laser_active: bool = False
        self.spotlight_active: bool = False
        self.dnd_active: bool = False
        self._fallback_pos = [960, 540]

    def _get_cursor_pos(self) -> tuple[int, int]:
        pos = self.mouse.position
        if pos is not None and len(pos) == 2 and pos[0] is not None and pos[1] is not None:
            self._fallback_pos = [int(pos[0]), int(pos[1])]
            return int(pos[0]), int(pos[1])
        return self._fallback_pos[0], self._fallback_pos[1]

    def _move_cursor_relative(self, ix: int, iy: int) -> None:
        if ix == 0 and iy == 0:
            return
        self._fallback_pos[0] += ix
        self._fallback_pos[1] += iy
        try:
            self.mouse.move(ix, iy)
        except TypeError:
            if platform.system() == "Windows":
                try:
                    ctypes.windll.user32.mouse_event(0x0001, ix, iy, 0, 0)
                except Exception:
                    pass

    def handle_slide(self, direction: str) -> None:
        if direction == "next":
            self.keyboard.press(Key.right)
            self.keyboard.release(Key.right)
            logger.info("Slide -> NEXT (Right Arrow)")
        elif direction == "prev":
            self.keyboard.press(Key.left)
            self.keyboard.release(Key.left)
            logger.info("Slide -> PREV (Left Arrow)")

    def handle_presentation(self, action: str) -> None:
        if action == "start":
            self.keyboard.press(Key.f5)
            self.keyboard.release(Key.f5)
            logger.info("Presentation -> START (F5)")
        elif action == "blackout":
            self.keyboard.press("b")
            self.keyboard.release("b")
            logger.info("Presentation -> BLACKOUT (B)")
        elif action == "esc":
            self.keyboard.press(Key.esc)
            self.keyboard.release(Key.esc)
            logger.info("Presentation -> EXIT (Esc)")

    def handle_move(self, dx: float, dy: float) -> None:
        ix, iy = int(round(dx)), int(round(dy))
        self._move_cursor_relative(ix, iy)
        if self.laser_active:
            cx, cy = self._get_cursor_pos()
            self.ui.set_laser(True, cx, cy)
        if self.spotlight_active:
            cx, cy = self._get_cursor_pos()
            self.ui.set_spotlight(True, cx, cy)

    def handle_click(self, button_name: str) -> None:
        btn = Button.right if button_name == "right" else Button.left
        try:
            self.mouse.click(btn, 1)
        except TypeError:
            pass
        logger.info("Mouse Click -> %s", button_name.upper())

    def handle_scroll(self, dy: float) -> None:
        steps = int(round(dy)) if abs(dy) >= 1.0 else (1 if dy > 0 else -1 if dy < 0 else 0)
        if steps != 0:
            try:
                self.mouse.scroll(0, steps)
            except TypeError:
                if platform.system() == "Windows":
                    try:
                        ctypes.windll.user32.mouse_event(0x0800, 0, 0, steps * 120, 0)
                    except Exception:
                        pass

    def handle_volume(self, action: str) -> None:
        key_map = {
            "up": Key.media_volume_up,
            "down": Key.media_volume_down,
            "mute": Key.media_volume_mute,
        }
        key = key_map.get(action)
        if key is not None:
            self.keyboard.press(key)
            self.keyboard.release(key)
            logger.info("Volume -> %s", action.upper())

    def handle_text(self, value: str) -> None:
        if not value:
            return
        special_keys = {
            "Backspace": Key.backspace,
            "BACKSPACE": Key.backspace,
            "\b": Key.backspace,
            "Enter": Key.enter,
            "ENTER": Key.enter,
            "\n": Key.enter,
            "Tab": Key.tab,
            "Escape": Key.esc,
        }
        if value in special_keys:
            k = special_keys[value]
            self.keyboard.press(k)
            self.keyboard.release(k)
            logger.info("Remote Key -> %s", value)
        else:
            self.keyboard.type(value)
            logger.info("Remote Text -> %r", value)

    def handle_laser(self, active: bool, dx: float = 0.0, dy: float = 0.0) -> None:
        self.laser_active = active
        if active and self.spotlight_active:
            self.spotlight_active = False
            self.ui.set_spotlight(False, 0, 0)
        ix, iy = int(round(dx)), int(round(dy))
        self._move_cursor_relative(ix, iy)
        cx, cy = self._get_cursor_pos()
        self.ui.set_laser(active, cx, cy)

    def handle_spotlight(self, active: bool, dx: float = 0.0, dy: float = 0.0) -> None:
        self.spotlight_active = active
        if active and self.laser_active:
            self.laser_active = False
            self.ui.set_laser(False, 0, 0)
        ix, iy = int(round(dx)), int(round(dy))
        self._move_cursor_relative(ix, iy)
        cx, cy = self._get_cursor_pos()
        self.ui.set_spotlight(active, cx, cy)

    def handle_dnd(self, active: bool) -> bool:
        self.dnd_active = active
        sys_name = platform.system()
        try:
            if sys_name == "Windows":
                import winreg
                key_path = r"Software\Microsoft\Windows\CurrentVersion\PushNotifications"
                with winreg.CreateKey(winreg.HKEY_CURRENT_USER, key_path) as reg_key:
                    toast_val = 0 if active else 1
                    winreg.SetValueEx(reg_key, "ToastEnabled", 0, winreg.REG_DWORD, toast_val)
                logger.info("Windows Do Not Disturb (Toast Suppression) -> %s", "ON" if active else "OFF")
            elif sys_name == "Darwin":
                logger.info("macOS Do Not Disturb -> %s", "ON" if active else "OFF")
            elif sys_name == "Linux":
                subprocess.run(
                    ["gsettings", "set", "org.gnome.desktop.notifications", "show-banners", str(not active).lower()],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                logger.info("Linux Do Not Disturb -> %s", "ON" if active else "OFF")
        except Exception as exc:
            logger.warning("DND toggle encountered non-fatal OS restriction: %s", exc)
        return self.dnd_active


class ApirServer:
    """
    Asynchronous WebSocket & HTTP/PWA Server managing the Apir QR Handshake and real-time events.
    """

    def __init__(
        self,
        host_ip: str,
        port: int,
        hostname: str,
        token: str,
        ui: ApirOverlayUI,
        executor: OSInputExecutor,
    ) -> None:
        self.host_ip = host_ip
        self.port = port
        self.hostname = hostname
        self.token = token
        self.ui = ui
        self.executor = executor
        self.authenticated_clients: Set[ServerConnection] = set()

    def process_request(
        self, connection: ServerConnection, request: Request
    ) -> Optional[Response]:
        """
        Serve the zero-install Cultural-Brand PWA Mobile Controller, `/manifest.json`,
        `/logo.png`, and `/show-qr` on regular HTTP GET requests while letting WebSocket
        upgrade requests pass through to `handler`.
        """
        upgrade = request.headers.get("Upgrade", "").lower()
        if upgrade == "websocket":
            return None

        req_path = request.path.split("?", 1)[0]
        if req_path == "/show-qr":
            self.ui.show_qr_popup()
            body = b'{"status":"focused"}'
            headers = Headers([
                ("Content-Type", "application/json"),
                ("Content-Length", str(len(body))),
            ])
            return Response(200, "OK", headers, body)

        if req_path == "/manifest.json":
            headers = Headers([
                ("Content-Type", "application/manifest+json; charset=utf-8"),
                ("Content-Length", str(len(PWA_MANIFEST_JSON))),
                ("Cache-Control", "no-cache"),
            ])
            return Response(200, "OK", headers, PWA_MANIFEST_JSON)

        if req_path in ("/logo.png", "/favicon.ico") and LOGO_PATH.exists():
            logo_bytes = LOGO_PATH.read_bytes()
            headers = Headers([
                ("Content-Type", "image/png"),
                ("Content-Length", str(len(logo_bytes))),
                ("Cache-Control", "public, max-age=3600"),
            ])
            return Response(200, "OK", headers, logo_bytes)

        html_bytes = render_mobile_web_html(token=self.token, host=self.hostname)
        headers = Headers([
            ("Content-Type", "text/html; charset=utf-8"),
            ("Content-Length", str(len(html_bytes))),
            ("Cache-Control", "no-store"),
        ])
        return Response(200, "OK", headers, html_bytes)

    async def handler(self, websocket: ServerConnection) -> None:
        peer = websocket.remote_address
        logger.info("Incoming WebSocket connection from %s", peer)
        is_authenticated = False

        try:
            async for raw_msg in websocket:
                try:
                    data = json.loads(raw_msg)
                except json.JSONDecodeError:
                    await websocket.send(json.dumps({
                        "type": "error",
                        "message": "Malformed JSON payload",
                    }))
                    continue

                msg_type = data.get("type")

                if msg_type == "handshake":
                    client_token = str(data.get("token", "")).strip()
                    if client_token == self.token:
                        is_authenticated = True
                        self.authenticated_clients.add(websocket)
                        self.ui.close_qr_popup()
                        logger.info("Apir! Handshake verified for client %s", peer)
                        await websocket.send(json.dumps({
                            "type": "handshake_ack",
                            "status": "ok",
                            "host": self.hostname,
                        }))
                    else:
                        logger.warning("Invalid handshake token %r from %s", client_token, peer)
                        await websocket.send(json.dumps({
                            "type": "handshake_ack",
                            "status": "error",
                            "message": "Invalid session PIN token",
                        }))
                    continue

                if not is_authenticated:
                    await websocket.send(json.dumps({
                        "type": "error",
                        "message": "Unauthorized: complete handshake first",
                    }))
                    continue

                if msg_type == "request_preview":
                    b64_jpg = await asyncio.to_thread(capture_screen_thumbnail_base64)
                    if b64_jpg:
                        await websocket.send(json.dumps({
                            "type": "preview_frame",
                            "image": b64_jpg,
                        }))
                    continue

                self._dispatch_command(msg_type, data)

                if data.get("ack"):
                    await websocket.send(json.dumps({
                        "type": "ack",
                        "command": msg_type,
                        "status": "ok",
                    }))

        except websockets.exceptions.ConnectionClosed:
            logger.info("Client %s disconnected", peer)
        finally:
            self.authenticated_clients.discard(websocket)
            if not self.authenticated_clients:
                self.executor.handle_laser(False)
                self.executor.handle_spotlight(False)

    def _dispatch_command(self, msg_type: Optional[str], data: Dict[str, Any]) -> None:
        if msg_type == "slide":
            direction = str(data.get("dir", "next")).lower()
            self.executor.handle_slide(direction)

        elif msg_type == "presentation":
            action = str(data.get("action", "start")).lower()
            self.executor.handle_presentation(action)

        elif msg_type == "move":
            dx = float(data.get("dx", 0.0))
            dy = float(data.get("dy", 0.0))
            self.executor.handle_move(dx, dy)

        elif msg_type == "click":
            button = str(data.get("button", "left")).lower()
            self.executor.handle_click(button)

        elif msg_type == "scroll":
            dy = float(data.get("dy", 0.0))
            self.executor.handle_scroll(dy)

        elif msg_type == "volume":
            action = str(data.get("action", "up")).lower()
            self.executor.handle_volume(action)

        elif msg_type == "text":
            value = str(data.get("value", ""))
            self.executor.handle_text(value)

        elif msg_type == "laser":
            active = bool(data.get("active", False))
            dx = float(data.get("dx", 0.0))
            dy = float(data.get("dy", 0.0))
            self.executor.handle_laser(active, dx, dy)

        elif msg_type == "spotlight":
            active = bool(data.get("active", False))
            dx = float(data.get("dx", 0.0))
            dy = float(data.get("dy", 0.0))
            self.executor.handle_spotlight(active, dx, dy)

        elif msg_type == "dnd":
            active = bool(data.get("active", False))
            self.executor.handle_dnd(active)

        else:
            logger.debug("Ignored unknown command type: %s", msg_type)


def register_mdns_service(ip: str, port: int, hostname: str) -> Optional[Tuple[Any, Any]]:
    """Advertise `_apir._tcp.local.` via mDNS/Bonjour (`zeroconf`) for zero-config discovery."""
    if not ZEROCONF_AVAILABLE:
        return None
    try:
        zc = Zeroconf()
        info = ServiceInfo(
            "_apir._tcp.local.",
            f"{hostname}._apir._tcp.local.",
            addresses=[socket.inet_aton(ip)],
            port=port,
            properties={
                "app": "apir",
                "host": hostname,
                "uri": f"ws://{ip}:{port}",
            },
            server=f"{hostname}.local.",
        )
        zc.register_service(info)
        logger.info("mDNS Bonjour service registered: %s._apir._tcp.local. (%s:%d)", hostname, ip, port)
        return zc, info
    except Exception as exc:
        logger.debug("mDNS registration skipped: %s", exc)
        return None


async def _async_websocket_daemon(
    apir_server: ApirServer,
    local_ip: str,
    port: int,
    hostname: str,
    uri: str,
) -> None:
    mdns_handle = await asyncio.to_thread(register_mdns_service, local_ip, port, hostname)
    stop_event = asyncio.Event()
    async with serve(
        apir_server.handler,
        "0.0.0.0",
        port,
        process_request=apir_server.process_request,
    ):
        logger.info("Apir Server listening on http://%s:%d & %s", local_ip, port, uri)
        try:
            await stop_event.wait()
        except asyncio.CancelledError:
            pass
        finally:
            if mdns_handle is not None:
                zc, info = mdns_handle
                try:
                    await asyncio.to_thread(zc.unregister_service, info)
                    await asyncio.to_thread(zc.close)
                except Exception:
                    pass


def start_application(port: int, fixed_token: Optional[str], headless: bool) -> None:
    if not ensure_single_instance_or_focus(port):
        # An existing Apir instance was already running and has been brought to focus!
        return

    interfaces = list_all_lan_interfaces()
    local_ip = interfaces[0][1]
    hostname = socket.gethostname()
    token = generate_session_pin(fixed_token)

    payload = build_pairing_payload(local_ip, port, hostname, token)
    payload_json = json.dumps(payload, separators=(",", ":"))
    pairing_url = build_pairing_url(payload, local_ip, port)

    qr_ascii = render_qr_ascii(pairing_url)
    banner = (
        "\n"
        "============================================================\n"
        "  APIR DESKTOP COMPANION - QR HIGH-FIVE PAIRING SERVER\n"
        "============================================================\n"
        f"  Host Name   : {hostname}\n"
        f"  WebSocket   : {payload['uri']}\n"
        f"  Mobile URL  : {pairing_url}\n"
        f"  Session PIN : {token}\n"
        f"  Interfaces  : {', '.join(f'{n}={ip}' for n, ip in interfaces)}\n"
        f"  QR Payload  : {payload_json}\n"
        "============================================================\n"
    )
    print(banner, flush=True)
    print(qr_ascii, flush=True)
    print("\nWaiting for Apir Mobile to scan QR code and complete handshake...\n", flush=True)

    ui = ApirOverlayUI(
        interfaces=interfaces,
        port=port,
        hostname=hostname,
        token=token,
        headless=headless,
    )
    executor = OSInputExecutor(ui=ui)
    apir_server = ApirServer(
        host_ip=local_ip,
        port=port,
        hostname=hostname,
        token=token,
        ui=ui,
        executor=executor,
    )

    if ui.headless:
        asyncio.run(_async_websocket_daemon(apir_server, local_ip, port, hostname, payload["uri"]))
    else:
        # Run asyncio WebSocket server in a background daemon thread so Tkinter owns
        # the Main Thread (required on Windows so the window never goes 'Not Responding')
        server_thread = threading.Thread(
            target=lambda: asyncio.run(
                _async_websocket_daemon(apir_server, local_ip, port, hostname, payload["uri"])
            ),
            name="ApirAsyncioThread",
            daemon=True,
        )
        server_thread.start()
        ui.run_main_loop()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apir Desktop Companion Server")
    parser.add_argument("--port", type=int, default=8765, help="WebSocket server port (default: 8765)")
    parser.add_argument("--token", type=str, default=None, help="Optional fixed 4-digit session PIN")
    parser.add_argument("--headless", action="store_true", help="Disable Tkinter popup window for CI/testing")
    return parser.parse_args()


if __name__ == "__main__":
    if sys.stdout is None:
        sys.stdout = io.StringIO()
    if sys.stderr is None:
        sys.stderr = io.StringIO()
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
            if hasattr(sys.stderr, "reconfigure"):
                sys.stderr.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    args = parse_args()
    try:
        start_application(port=args.port, fixed_token=args.token, headless=args.headless)
    except KeyboardInterrupt:
        logger.info("Apir server stopped by user.")
        sys.exit(0)
