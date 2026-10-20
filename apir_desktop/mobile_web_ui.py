"""
Embedded Zero-Install Mobile Controller Web UI & PWA Manifest for Apir Desktop Server.
Uses the official Apir Cultural Brand Identity:
- Scaffold / Background Color: Deep Maroon (`#561217`)
- Primary Accent & Normal Trackpad Glow: Golden Amber (`#F59E1D`)
- Secondary Surface & Inactive Trackpad Dots: Warm Cream (`#FDECC8` at 25% opacity)
- Active Laser Mode Glow: Crimson Red (`#9E1F36`)
- Secondary Tech / Connected Status Accent: Royal Blue (`#2B62A7`)
- Typography: `Tribo` for headers/logo ("APIR") & `Garet` for body/buttons
  (with fallback to `Montserrat` / `Plus Jakarta Sans`).
"""

import json

PWA_MANIFEST_JSON = json.dumps({
    "name": "Apir Presenter Remote",
    "short_name": "Apir",
    "description": "Adaptive Presentation Interface & Remote — QR Pairing Edition",
    "start_url": "/",
    "display": "standalone",
    "orientation": "portrait",
    "background_color": "#561217",
    "theme_color": "#561217",
    "icons": [
        {
            "src": "/logo.png",
            "sizes": "512x512",
            "type": "image/png",
            "purpose": "any maskable",
        }
    ],
}, indent=2).encode("utf-8")


MOBILE_WEB_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
<meta name="theme-color" content="#561217" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<link rel="manifest" href="/manifest.json" />
<link rel="icon" type="image/png" href="/logo.png" />
<link rel="apple-touch-icon" href="/logo.png" />
<title>Apir Presenter Remote</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@500;600;700;800&family=Plus+Jakarta+Sans:wght@500;600;700;800&display=swap" rel="stylesheet">
<style>
  :root {
    --deep-maroon: #561217;
    --dark-maroon-surface: #3D0C10;
    --golden-amber: #F59E1D;
    --warm-cream: #FDECC8;
    --warm-cream-25: rgba(253, 236, 200, 0.25);
    --crimson-red: #9E1F36;
    --royal-blue: #2B62A7;
    --font-header: 'Tribo', 'Montserrat', 'Plus Jakarta Sans', sans-serif;
    --font-body: 'Garet', 'Montserrat', 'Plus Jakarta Sans', sans-serif;
  }
  * {
    box-sizing: border-box;
    user-select: none;
    -webkit-user-select: none;
    -webkit-touch-callout: none;
  }
  html, body {
    margin: 0;
    padding: 0;
    width: 100%;
    height: 100%;
    background: var(--deep-maroon);
    color: var(--warm-cream);
    font-family: var(--font-body);
    overflow: hidden;
    touch-action: none;
  }
  .app-shell {
    display: flex;
    flex-direction: column;
    width: 100%;
    height: 100dvh;
    padding: 10px 14px 14px 14px;
    gap: 8px;
  }
  /* 1. Top Status Bar */
  .top-bar {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 42px;
    flex-shrink: 0;
  }
  .status-pill {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 8px;
    background: var(--warm-cream-25);
    border: 1.4px solid var(--royal-blue);
    border-radius: 999px;
    padding: 7px 12px;
    min-width: 0;
    transition: border-color 0.2s;
  }
  .status-pill.laser-mode {
    border-color: var(--crimson-red);
  }
  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--royal-blue);
    box-shadow: 0 0 8px var(--royal-blue);
    flex-shrink: 0;
  }
  .status-dot.laser-mode {
    background: var(--crimson-red);
    box-shadow: 0 0 10px var(--crimson-red);
  }
  .status-dot.disconnected {
    background: var(--crimson-red);
    box-shadow: 0 0 8px var(--crimson-red);
  }
  .logo-badge {
    width: 24px;
    height: 24px;
    border-radius: 7px;
    border: 1.4px solid var(--golden-amber);
    object-fit: cover;
    flex-shrink: 0;
  }
  .logo-word {
    font-family: var(--font-header);
    font-weight: 800;
    letter-spacing: 1.4px;
    color: var(--golden-amber);
    font-size: 12.5px;
  }
  .status-text {
    font-size: 12px;
    font-weight: 600;
    color: var(--warm-cream);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .timer-pill {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 7px 10px;
    border-radius: 999px;
    background: var(--warm-cream-25);
    border: 1.2px solid rgba(245, 158, 29, 0.5);
    color: var(--golden-amber);
    font-size: 11.5px;
    font-weight: 800;
    cursor: pointer;
    flex-shrink: 0;
  }
  .timer-pill.running {
    background: rgba(245, 158, 29, 0.25);
    border-color: var(--golden-amber);
  }
  .icon-btn {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: var(--warm-cream-25);
    border: 1.2px solid var(--warm-cream-25);
    color: var(--warm-cream);
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    flex-shrink: 0;
    padding: 0;
    font-size: 15px;
  }
  .icon-btn.active-lock {
    background: rgba(245, 158, 29, 0.28);
    border-color: var(--golden-amber);
    color: var(--golden-amber);
  }
  .icon-btn.active-kbd {
    background: rgba(43, 98, 167, 0.32);
    border-color: var(--royal-blue);
    color: var(--warm-cream);
  }

  /* 2. Interactive Dot-Matrix Trackpad (Upper 63%) */
  .trackpad-wrap {
    position: relative;
    flex: 63;
    background: var(--dark-maroon-surface);
    border: 1.5px solid var(--warm-cream-25);
    border-radius: 26px;
    overflow: hidden;
    transition: border-color 0.15s;
  }
  .trackpad-wrap.touch-active {
    border-color: var(--golden-amber);
  }
  .trackpad-wrap.laser-active {
    border-color: var(--crimson-red);
  }
  .trackpad-preview-img {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    opacity: 0.38;
    pointer-events: none;
    display: none;
  }
  .trackpad-watermark {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    width: 136px;
    height: 136px;
    border-radius: 30px;
    opacity: 0.14;
    pointer-events: none;
    object-fit: cover;
  }
  canvas#trackpadCanvas {
    position: relative;
    width: 100%;
    height: 100%;
    display: block;
    z-index: 2;
  }
  .trackpad-hint {
    position: absolute;
    left: 16px;
    right: 16px;
    bottom: 12px;
    display: flex;
    justify-content: space-between;
    pointer-events: none;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 1.1px;
    color: rgba(253, 236, 200, 0.55);
    z-index: 3;
  }

  /* 3. Bottom Presenter Control Dock (Lower 37%) */
  .bottom-dock {
    flex: 37;
    display: flex;
    flex-direction: column;
    justify-content: space-evenly;
    gap: 6px;
  }
  .utility-row {
    display: flex;
    justify-content: space-around;
    align-items: center;
    padding: 0 4px;
  }
  .util-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
  }
  .util-circle {
    width: 52px;
    height: 52px;
    border-radius: 50%;
    background: var(--warm-cream-25);
    border: 1.3px solid var(--warm-cream-25);
    color: var(--warm-cream);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 19px;
    transition: all 0.15s;
  }
  .util-circle.active-laser {
    background: rgba(158, 31, 54, 0.55);
    border-color: var(--crimson-red);
    color: var(--warm-cream);
    box-shadow: 0 0 16px rgba(158, 31, 54, 0.85);
  }
  .util-circle.active-vol {
    background: rgba(245, 158, 29, 0.30);
    border-color: var(--golden-amber);
    color: var(--golden-amber);
    box-shadow: 0 0 14px rgba(245, 158, 29, 0.45);
  }
  .util-circle.active-dnd {
    background: rgba(43, 98, 167, 0.38);
    border-color: var(--royal-blue);
    color: var(--warm-cream);
    box-shadow: 0 0 14px rgba(43, 98, 167, 0.55);
  }
  .util-label {
    font-size: 10.5px;
    font-weight: 600;
    color: rgba(253, 236, 200, 0.85);
  }

  .slide-row {
    display: flex;
    gap: 14px;
    height: 72px;
  }
  .slide-btn {
    border-radius: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    font-family: var(--font-body);
    font-size: 14px;
    font-weight: 800;
    letter-spacing: 1.4px;
    cursor: pointer;
    transition: transform 0.08s;
  }
  .slide-btn:active {
    transform: scale(0.96);
  }
  .slide-prev {
    flex: 1;
    background: var(--warm-cream-25);
    border: 1.5px solid rgba(253, 236, 200, 0.45);
    color: var(--warm-cream);
  }
  .slide-next {
    flex: 2;
    background: var(--golden-amber);
    border: 1.5px solid var(--golden-amber);
    color: var(--deep-maroon);
    box-shadow: 0 0 16px rgba(245, 158, 29, 0.35);
  }

  /* Overlays: Volume/Tools & Remote Keyboard */
  .overlay-box {
    position: absolute;
    left: 16px;
    right: 16px;
    background: rgba(86, 18, 23, 0.97);
    border: 1.4px solid var(--golden-amber);
    border-radius: 18px;
    padding: 12px 14px;
    z-index: 50;
    display: none;
  }
  .overlay-box.show {
    display: flex;
  }
  #kbdOverlay {
    top: 56px;
    align-items: center;
    gap: 8px;
  }
  #kbdInput {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: var(--warm-cream);
    font-family: var(--font-body);
    font-size: 14px;
  }
  #kbdInput::placeholder {
    color: rgba(253, 236, 200, 0.55);
  }
  #volOverlay {
    bottom: 152px;
    flex-direction: column;
    gap: 10px;
  }
  .vol-row {
    display: flex;
    justify-content: space-around;
    gap: 8px;
  }
  .vol-btn {
    flex: 1;
    background: var(--warm-cream-25);
    border: 1px solid var(--golden-amber);
    color: var(--warm-cream);
    border-radius: 12px;
    padding: 9px 10px;
    font-family: var(--font-body);
    font-weight: 700;
    font-size: 12.5px;
    text-align: center;
  }
</style>
</head>
<body>
<div class="app-shell">
  <!-- 1. Top Status Bar -->
  <div class="top-bar">
    <div class="status-pill" id="statusPill">
      <img src="/logo.png" alt="Apir" class="logo-badge" />
      <div class="status-dot" id="statusDot"></div>
      <span class="logo-word">APIR!</span>
      <div class="status-text" id="statusText">Connecting...</div>
    </div>
    <div class="timer-pill" id="timerPill" title="Tap: Start/Pause • Double-Tap: Change Duration">⏱ <span id="timerText">15:00</span></div>
    <button class="icon-btn" id="lockBtn" title="Presenter Lock">🔒</button>
    <button class="icon-btn" id="kbdBtn" title="Remote Keyboard & Voice Dictation">🎙️</button>
    <button class="icon-btn" id="reconnectBtn" title="Reconnect">🔄</button>
  </div>

  <!-- Hidden/Overlay Remote Keyboard & Dictation Bar -->
  <div class="overlay-box" id="kbdOverlay">
    <input id="kbdInput" type="text" placeholder="Type or use phone mic to dictate..." autocomplete="off" />
    <button class="vol-btn" style="flex:0;padding:8px 14px;" id="enterKeyBtn">↵</button>
    <button class="vol-btn" style="flex:0;padding:8px 14px;" id="bkspKeyBtn">⌫</button>
  </div>

  <!-- 2. Interactive Dot-Matrix Trackpad -->
  <div class="trackpad-wrap" id="trackpadWrap">
    <img id="slidePreviewImg" class="trackpad-preview-img" alt="Slide Preview" />
    <img src="/logo.png" alt="" class="trackpad-watermark" id="logoWatermark" />
    <canvas id="trackpadCanvas"></canvas>
    <div class="trackpad-hint">
      <span id="modeHint">1F MOVE/TAP • 2F RIGHT-CLICK/SCROLL</span>
      <span id="dndHint" style="color:#2B62A7;display:none;">🌙 DND ON</span>
    </div>
  </div>

  <!-- Quick Volume & Presentation Shortcuts Popover -->
  <div class="overlay-box" id="volOverlay">
    <div class="vol-row">
      <button class="vol-btn" id="volDownBtn">🔉 Vol -</button>
      <button class="vol-btn" id="volMuteBtn">🔇 Mute</button>
      <button class="vol-btn" id="volUpBtn">🔊 Vol +</button>
    </div>
    <div class="vol-row">
      <button class="vol-btn" id="startPresBtn">▶️ Start (F5)</button>
      <button class="vol-btn" id="blackoutBtn">⬛ Blackout (B)</button>
      <button class="vol-btn" id="escPresBtn">⏹️ Exit (Esc)</button>
    </div>
  </div>

  <!-- 3. Bottom Presenter Control Dock -->
  <div class="bottom-dock">
    <div class="utility-row">
      <div class="util-item">
        <button class="util-circle" id="laserBtn">🎯</button>
        <span class="util-label">Laser</span>
      </div>
      <div class="util-item">
        <button class="util-circle" id="spotlightBtn">🔦</button>
        <span class="util-label">Spotlight</span>
      </div>
      <div class="util-item">
        <button class="util-circle" id="previewBtn">🖼️</button>
        <span class="util-label">Slide View</span>
      </div>
      <div class="util-item">
        <button class="util-circle" id="volBtn">🔊</button>
        <span class="util-label">Media/F5</span>
      </div>
      <div class="util-item">
        <button class="util-circle" id="dndBtn">🌙</button>
        <span class="util-label">DND</span>
      </div>
    </div>

    <div class="slide-row">
      <button class="slide-btn slide-prev" id="prevSlideBtn">‹ PREV</button>
      <button class="slide-btn slide-next" id="nextSlideBtn">NEXT SLIDE ›</button>
    </div>
  </div>
</div>

<script>
(function() {
  const params = new URLSearchParams(window.location.search);
  const token = params.get('token') || '__DEFAULT_TOKEN__';
  const hostLabel = params.get('host') || '__DEFAULT_HOST__';
  const wsProto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUri = params.get('uri') || (wsProto + '//' + window.location.host);

  let ws = null;
  let isConnected = false;
  let presenterLocked = false;
  let laserActive = false;
  let spotlightActive = false;
  let previewActive = false;
  let previewTimer = null;
  let dndActive = false;

  const statusPill = document.getElementById('statusPill');
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  const trackpadWrap = document.getElementById('trackpadWrap');
  const slidePreviewImg = document.getElementById('slidePreviewImg');
  const canvas = document.getElementById('trackpadCanvas');
  const ctx = canvas.getContext('2d');
  const modeHint = document.getElementById('modeHint');
  const dndHint = document.getElementById('dndHint');

  function haptic(ms) {
    if (navigator.vibrate) {
      try { navigator.vibrate(ms); } catch (_) {}
    }
  }

  function sendCmd(payload) {
    if (ws && ws.readyState === WebSocket.OPEN && isConnected) {
      ws.send(JSON.stringify(payload));
    }
  }

  function connectSocket() {
    statusText.textContent = 'Connecting to ' + hostLabel + '...';
    ws = new WebSocket(wsUri);

    ws.onopen = function() {
      ws.send(JSON.stringify({ type: 'handshake', token: token }));
    };

    ws.onmessage = function(ev) {
      try {
        const data = JSON.parse(ev.data);
        if (data.type === 'handshake_ack') {
          if (data.status === 'ok') {
            isConnected = true;
            statusDot.classList.remove('disconnected');
            statusText.textContent = 'Connected to ' + (data.host || hostLabel);
            haptic([40, 60, 90]);
          } else {
            statusDot.classList.add('disconnected');
            statusText.textContent = 'PIN Error: ' + (data.message || 'Invalid token');
          }
        } else if (data.type === 'preview_frame' && data.image) {
          slidePreviewImg.src = 'data:image/jpeg;base64,' + data.image;
          slidePreviewImg.style.display = previewActive ? 'block' : 'none';
        }
      } catch (_) {}
    };

    ws.onclose = function() {
      isConnected = false;
      statusDot.classList.add('disconnected');
      statusText.textContent = 'Disconnected • Tap 🔄';
    };
  }

  connectSocket();
  document.getElementById('reconnectBtn').addEventListener('click', function() {
    haptic(20);
    connectSocket();
  });

  // Presentation Countdown Timer with 5m / 1m / 0m Haptic Alerts
  const presets = [15 * 60, 30 * 60, 10 * 60, 5 * 60];
  let presetIdx = 0;
  let remainingSecs = presets[0];
  let timerRunning = false;
  let lastTimerTap = 0;
  const timerPill = document.getElementById('timerPill');
  const timerText = document.getElementById('timerText');

  function formatTime(secs) {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
  }

  setInterval(function() {
    if (!timerRunning || remainingSecs <= 0) return;
    remainingSecs--;
    timerText.textContent = formatTime(remainingSecs);
    if (remainingSecs === 300 || remainingSecs === 60) {
      haptic([80, 60, 80]);
    } else if (remainingSecs === 0) {
      timerRunning = false;
      timerPill.classList.remove('running');
      haptic([150, 80, 150, 80, 200]);
    }
  }, 1000);

  timerPill.addEventListener('click', function() {
    const now = Date.now();
    if (now - lastTimerTap < 320) {
      // Double tap -> cycle duration preset
      presetIdx = (presetIdx + 1) % presets.length;
      remainingSecs = presets[presetIdx];
      timerRunning = false;
      timerPill.classList.remove('running');
      timerText.textContent = formatTime(remainingSecs);
      haptic(40);
    } else {
      timerRunning = !timerRunning;
      timerPill.classList.toggle('running', timerRunning);
      haptic(25);
    }
    lastTimerTap = now;
  });

  // Presenter Lock
  const lockBtn = document.getElementById('lockBtn');
  lockBtn.addEventListener('click', function() {
    haptic(30);
    presenterLocked = !presenterLocked;
    lockBtn.classList.toggle('active-lock', presenterLocked);
    if (presenterLocked) {
      document.getElementById('kbdOverlay').classList.remove('show');
      document.getElementById('volOverlay').classList.remove('show');
    }
    updateHints();
    drawDots();
  });

  function updateHints() {
    if (laserActive) {
      modeHint.textContent = 'VIRTUAL LASER POINTER ACTIVE';
      modeHint.style.color = '#9E1F36';
    } else if (spotlightActive) {
      modeHint.textContent = 'SPOTLIGHT BEAM ACTIVE';
      modeHint.style.color = '#F59E1D';
    } else if (presenterLocked) {
      modeHint.textContent = 'PRESENTER LOCK • CLICKS DISABLED';
      modeHint.style.color = '#F59E1D';
    } else {
      modeHint.textContent = '1F MOVE/TAP • 2F RIGHT-CLICK/SCROLL';
      modeHint.style.color = 'rgba(253, 236, 200, 0.55)';
    }
  }

  // Remote Keyboard & Voice Dictation
  const kbdBtn = document.getElementById('kbdBtn');
  const kbdOverlay = document.getElementById('kbdOverlay');
  const kbdInput = document.getElementById('kbdInput');
  kbdBtn.addEventListener('click', function() {
    if (presenterLocked) { haptic([30, 40]); return; }
    haptic(20);
    const showing = kbdOverlay.classList.toggle('show');
    kbdBtn.classList.toggle('active-kbd', showing);
    if (showing) {
      kbdInput.value = '';
      kbdInput.focus();
    } else {
      kbdInput.blur();
    }
  });

  let prevKbdVal = '';
  kbdInput.addEventListener('input', function() {
    if (presenterLocked) return;
    const val = kbdInput.value;
    if (val.length < prevKbdVal.length) {
      sendCmd({ type: 'text', value: 'Backspace' });
    } else if (val.length > prevKbdVal.length) {
      const delta = val.slice(prevKbdVal.length);
      sendCmd({ type: 'text', value: delta });
    }
    prevKbdVal = val;
  });
  document.getElementById('enterKeyBtn').addEventListener('click', function() {
    haptic(20);
    sendCmd({ type: 'text', value: 'Enter' });
    kbdInput.value = '';
    prevKbdVal = '';
  });
  document.getElementById('bkspKeyBtn').addEventListener('click', function() {
    haptic(15);
    sendCmd({ type: 'text', value: 'Backspace' });
  });

  // Slide Buttons (also refresh slide preview if active)
  function triggerSlide(dir) {
    sendCmd({ type: 'slide', dir: dir });
    if (previewActive) {
      setTimeout(function() { sendCmd({ type: 'request_preview' }); }, 180);
    }
  }
  document.getElementById('prevSlideBtn').addEventListener('click', function() {
    haptic(35);
    triggerSlide('prev');
  });
  document.getElementById('nextSlideBtn').addEventListener('click', function() {
    haptic(55);
    triggerSlide('next');
  });

  // Laser & Spotlight Buttons
  const laserBtn = document.getElementById('laserBtn');
  const spotlightBtn = document.getElementById('spotlightBtn');

  function setLaser(state) {
    laserActive = state;
    if (laserActive && spotlightActive) {
      spotlightActive = false;
      spotlightBtn.classList.remove('active-vol');
      sendCmd({ type: 'spotlight', active: false, dx: 0, dy: 0 });
    }
    laserBtn.classList.toggle('active-laser', laserActive);
    statusPill.classList.toggle('laser-mode', laserActive);
    statusDot.classList.toggle('laser-mode', laserActive);
    trackpadWrap.classList.toggle('laser-active', laserActive);
    sendCmd({ type: 'laser', active: laserActive, dx: 0, dy: 0 });
    updateHints();
    drawDots();
  }

  function setSpotlight(state) {
    spotlightActive = state;
    if (spotlightActive && laserActive) {
      laserActive = false;
      laserBtn.classList.remove('active-laser');
      sendCmd({ type: 'laser', active: false, dx: 0, dy: 0 });
    }
    spotlightBtn.classList.toggle('active-vol', spotlightActive);
    sendCmd({ type: 'spotlight', active: spotlightActive, dx: 0, dy: 0 });
    updateHints();
    drawDots();
  }

  laserBtn.addEventListener('click', function() {
    haptic(35);
    setLaser(!laserActive);
  });
  spotlightBtn.addEventListener('click', function() {
    haptic(35);
    setSpotlight(!spotlightActive);
  });

  // Live Slide Preview Toggle
  const previewBtn = document.getElementById('previewBtn');
  previewBtn.addEventListener('click', function() {
    haptic(25);
    previewActive = !previewActive;
    previewBtn.classList.toggle('active-dnd', previewActive);
    if (previewActive) {
      sendCmd({ type: 'request_preview' });
      previewTimer = setInterval(function() {
        sendCmd({ type: 'request_preview' });
      }, 1500);
    } else {
      if (previewTimer) clearInterval(previewTimer);
      slidePreviewImg.style.display = 'none';
    }
  });

  // Volume & Presentation Shortcuts Popover
  const volBtn = document.getElementById('volBtn');
  const volOverlay = document.getElementById('volOverlay');
  volBtn.addEventListener('click', function() {
    if (presenterLocked) return;
    haptic(20);
    const showing = volOverlay.classList.toggle('show');
    volBtn.classList.toggle('active-vol', showing);
  });
  document.getElementById('volUpBtn').addEventListener('click', function() {
    haptic(20);
    sendCmd({ type: 'volume', action: 'up' });
  });
  document.getElementById('volDownBtn').addEventListener('click', function() {
    haptic(20);
    sendCmd({ type: 'volume', action: 'down' });
  });
  document.getElementById('volMuteBtn').addEventListener('click', function() {
    haptic(30);
    sendCmd({ type: 'volume', action: 'mute' });
  });
  document.getElementById('startPresBtn').addEventListener('click', function() {
    haptic(40);
    sendCmd({ type: 'presentation', action: 'start' });
    volOverlay.classList.remove('show');
    volBtn.classList.remove('active-vol');
  });
  document.getElementById('blackoutBtn').addEventListener('click', function() {
    haptic(35);
    sendCmd({ type: 'presentation', action: 'blackout' });
  });
  document.getElementById('escPresBtn').addEventListener('click', function() {
    haptic(35);
    sendCmd({ type: 'presentation', action: 'esc' });
    volOverlay.classList.remove('show');
    volBtn.classList.remove('active-vol');
  });

  // Do Not Disturb
  const dndBtn = document.getElementById('dndBtn');
  dndBtn.addEventListener('click', function() {
    if (presenterLocked) return;
    haptic(35);
    dndActive = !dndActive;
    dndBtn.classList.toggle('active-dnd', dndActive);
    dndHint.style.display = dndActive ? 'inline' : 'none';
    sendCmd({ type: 'dnd', active: dndActive });
  });

  // Interactive Dot-Matrix Trackpad Canvas
  let touchPos = null;
  let lastTouchX = 0;
  let lastTouchY = 0;
  let touchStartTime = 0;
  let totalDrag = 0;
  let maxTouches = 0;

  function resizeCanvas() {
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * window.devicePixelRatio;
    canvas.height = rect.height * window.devicePixelRatio;
    ctx.setTransform(window.devicePixelRatio, 0, 0, window.devicePixelRatio, 0, 0);
    drawDots();
  }
  window.addEventListener('resize', resizeCanvas);

  function drawDots() {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    ctx.clearRect(0, 0, w, h);

    const spacing = 24;
    const baseRadius = 1.75;
    const influence = 115;
    const cols = Math.floor(w / spacing);
    const rows = Math.floor(h / spacing);
    const startX = (w - (cols - 1) * spacing) / 2;
    const startY = (h - (rows - 1) * spacing) / 2;

    if (touchPos) {
      const grad = ctx.createRadialGradient(
        touchPos.x, touchPos.y, 2,
        touchPos.x, touchPos.y, influence
      );
      grad.addColorStop(0, laserActive ? 'rgba(158, 31, 54, 0.38)' : 'rgba(245, 158, 29, 0.28)');
      grad.addColorStop(1, 'rgba(0, 0, 0, 0)');
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.arc(touchPos.x, touchPos.y, influence, 0, Math.PI * 2);
      ctx.fill();
    }

    for (let r = 0; r < rows; r++) {
      const y = startY + r * spacing;
      for (let c = 0; c < cols; c++) {
        const x = startX + c * spacing;
        let radius = baseRadius;
        let fill = 'rgba(253, 236, 200, 0.25)';

        if (touchPos) {
          const dx = x - touchPos.x;
          const dy = y - touchPos.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < influence) {
            const t = 1 - dist / influence;
            const eased = t * t * (3 - 2 * t);
            radius = baseRadius + 3.4 * eased;
            fill = laserActive
              ? `rgba(158, 31, 54, ${0.35 + 0.65 * eased})`
              : `rgba(245, 158, 29, ${0.35 + 0.65 * eased})`;
          }
        }

        ctx.fillStyle = fill;
        ctx.beginPath();
        ctx.arc(x, y, radius, 0, Math.PI * 2);
        ctx.fill();
      }
    }
  }

  canvas.addEventListener('touchstart', function(e) {
    e.preventDefault();
    const rect = canvas.getBoundingClientRect();
    const t = e.touches[0];
    lastTouchX = t.clientX - rect.left;
    lastTouchY = t.clientY - rect.top;
    touchPos = { x: lastTouchX, y: lastTouchY };

    if (e.touches.length === 1) {
      touchStartTime = Date.now();
      totalDrag = 0;
      maxTouches = 1;
    } else if (e.touches.length > maxTouches) {
      maxTouches = e.touches.length;
    }
    trackpadWrap.classList.add('touch-active');
    drawDots();
  }, { passive: false });

  canvas.addEventListener('touchmove', function(e) {
    e.preventDefault();
    const rect = canvas.getBoundingClientRect();
    const t = e.touches[0];
    const curX = t.clientX - rect.left;
    const curY = t.clientY - rect.top;
    const dx = (curX - lastTouchX) * 1.75;
    const dy = (curY - lastTouchY) * 1.75;
    totalDrag += Math.hypot(curX - lastTouchX, curY - lastTouchY);
    lastTouchX = curX;
    lastTouchY = curY;
    touchPos = { x: curX, y: curY };

    if (e.touches.length === 1) {
      if (laserActive) {
        sendCmd({ type: 'laser', active: true, dx: dx, dy: dy });
      } else if (spotlightActive) {
        sendCmd({ type: 'spotlight', active: true, dx: dx, dy: dy });
      } else {
        sendCmd({ type: 'move', dx: dx, dy: dy });
      }
    } else if (e.touches.length >= 2 && !presenterLocked) {
      if (Math.abs(dy) > 0.5) {
        sendCmd({ type: 'scroll', dy: -dy * 0.15 });
      }
    }
    drawDots();
  }, { passive: false });

  canvas.addEventListener('touchend', function(e) {
    e.preventDefault();
    if (e.touches.length === 0) {
      const elapsed = Date.now() - touchStartTime;
      if (!presenterLocked && !laserActive && !spotlightActive && elapsed < 250 && totalDrag < 12) {
        if (maxTouches === 1) {
          haptic(15);
          sendCmd({ type: 'click', button: 'left' });
        } else if (maxTouches === 2) {
          haptic(25);
          sendCmd({ type: 'click', button: 'right' });
        }
      }
      touchPos = null;
      trackpadWrap.classList.remove('touch-active');
      drawDots();
    }
  }, { passive: false });

  setTimeout(resizeCanvas, 50);
})();
</script>
</body>
</html>
"""


def render_mobile_web_html(token: str, host: str) -> bytes:
    html = (
        MOBILE_WEB_HTML
        .replace("__DEFAULT_TOKEN__", token)
        .replace("__DEFAULT_HOST__", host)
    )
    return html.encode("utf-8")
