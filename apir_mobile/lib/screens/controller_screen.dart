import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../services/apir_socket_service.dart';

/// Official Cultural Brand Presenter Controller Screen:
/// - Scaffold / Background Color: Deep Maroon (`#561217`)
/// - Primary Accent & Normal Trackpad Glow: Golden Amber (`#F59E1D`)
/// - Secondary Surface & Inactive Trackpad Dots: Warm Cream (`#FDECC8` at 25% opacity)
/// - Active Laser Mode Glow: Crimson Red (`#9E1F36`)
/// - Secondary Tech / Connected Status Accent: Royal Blue (`#2B62A7`)
/// - Typography: `Tribo` for headers/logo and `Garet` for body/buttons
class ControllerScreen extends StatefulWidget {
  final ApirSocketService socketService;

  const ControllerScreen({
    super.key,
    required this.socketService,
  });

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen>
    with WidgetsBindingObserver {
  // Sentinel prefix to reliably detect Backspace on soft keyboards
  static const String _sentinel = '\u200B';

  final FocusNode _keyboardFocusNode = FocusNode();
  late final TextEditingController _keyboardController;
  String _previousText = _sentinel;

  // Presenter state flags
  bool _presenterLocked = false;
  bool _laserModeActive = false;
  bool _spotlightModeActive = false;
  bool _slidePreviewActive = false;
  bool _dndActive = false;
  bool _keyboardOverlayVisible = false;
  bool _volumePopoverVisible = false;
  double _virtualVolumeLevel = 0.70;
  bool _isMuted = false;

  // Presentation Countdown Timer (with 5m / 1m / 0m Haptic Alerts)
  static const List<int> _timerPresetsSeconds = <int>[900, 1800, 600, 300];
  int _timerPresetIdx = 0;
  int _remainingSeconds = 900;
  bool _timerRunning = false;
  Timer? _countdownTimer;
  Timer? _previewRefreshTimer;

  // Multi-touch trackpad gesture state (ValueNotifier avoids full widget-tree rebuilds at 120Hz)
  final ValueNotifier<Offset?> _touchPointNotifier =
      ValueNotifier<Offset?>(null);
  final Map<int, Offset> _activePointers = <int, Offset>{};
  int _maxPointersInGesture = 0;
  DateTime? _gestureStartTime;
  double _totalGestureDragDistance = 0.0;
  double _pendingDx = 0.0;
  double _pendingDy = 0.0;
  double _pendingScrollDy = 0.0;
  bool _frameFlushScheduled = false;

  static const double _scrollSensitivity = 0.22;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardController = TextEditingController(text: _sentinel);
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_timerRunning || _remainingSeconds <= 0) return;
      setState(() {
        _remainingSeconds--;
      });
      if (_remainingSeconds == 300 || _remainingSeconds == 60) {
        HapticFeedback.heavyImpact();
      } else if (_remainingSeconds == 0) {
        _timerRunning = false;
        HapticFeedback.vibrate();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.socketService.retryNowIfDisconnected();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _countdownTimer?.cancel();
    _previewRefreshTimer?.cancel();
    if (_laserModeActive) {
      widget.socketService.sendLaser(active: false);
    }
    if (_spotlightModeActive) {
      widget.socketService.sendSpotlight(active: false);
    }
    _touchPointNotifier.dispose();
    _keyboardFocusNode.dispose();
    _keyboardController.dispose();
    super.dispose();
  }

  void _triggerSlide(String dir) {
    widget.socketService.sendSlide(dir);
    if (_slidePreviewActive) {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (mounted && _slidePreviewActive) {
          widget.socketService.requestPreview();
        }
      });
    }
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
        HapticFeedback.mediumImpact();
        _triggerSlide('next');
        return true;
      } else if (event.logicalKey == LogicalKeyboardKey.audioVolumeDown) {
        HapticFeedback.mediumImpact();
        _triggerSlide('prev');
        return true;
      }
    }
    return false;
  }

  String _formatTimer(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _togglePresentationTimer() {
    HapticFeedback.selectionClick();
    setState(() {
      _timerRunning = !_timerRunning;
    });
  }

  void _cycleTimerPreset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _timerPresetIdx = (_timerPresetIdx + 1) % _timerPresetsSeconds.length;
      _remainingSeconds = _timerPresetsSeconds[_timerPresetIdx];
      _timerRunning = false;
    });
  }

  void _toggleSpotlightMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      _spotlightModeActive = !_spotlightModeActive;
      if (_spotlightModeActive && _laserModeActive) {
        _laserModeActive = false;
        widget.socketService.sendLaser(active: false);
      }
    });
    widget.socketService.sendSpotlight(active: _spotlightModeActive);
  }

  void _toggleSlidePreview() {
    HapticFeedback.lightImpact();
    setState(() {
      _slidePreviewActive = !_slidePreviewActive;
    });
    _previewRefreshTimer?.cancel();
    if (_slidePreviewActive) {
      widget.socketService.requestPreview();
      _previewRefreshTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => widget.socketService.requestPreview(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Remote Keyboard & Voice Dictation Streaming
  // ---------------------------------------------------------------------------
  void _toggleKeyboardInput() {
    if (_presenterLocked) {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(milliseconds: 1200),
          backgroundColor: ApirBrand.darkMaroonSurface,
          content: Text(
            'Presenter Lock is active. Unlock to use remote keyboard/dictation.',
            style: TextStyle(
              color: ApirBrand.warmCream,
              fontFamily: ApirBrand.bodyFontFamily,
              fontFamilyFallback: ApirBrand.fontFallbacks,
              fontSize: 12.5,
            ),
          ),
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _keyboardOverlayVisible = !_keyboardOverlayVisible;
    });

    if (_keyboardOverlayVisible) {
      _resetKeyboardBuffer();
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(_keyboardFocusNode);
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        }
      });
    } else {
      _keyboardFocusNode.unfocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
  }

  void _resetKeyboardBuffer() {
    _previousText = _sentinel;
    _keyboardController.value = const TextEditingValue(
      text: _sentinel,
      selection: TextSelection.collapsed(offset: 1),
    );
  }

  void _onRemoteTextChanged(String currentText) {
    if (_presenterLocked) return;

    if (currentText.isEmpty) {
      widget.socketService.sendText('Backspace');
      HapticFeedback.selectionClick();
      _resetKeyboardBuffer();
      return;
    }

    if (currentText.length < _previousText.length) {
      final deletedCount = _previousText.length - currentText.length;
      for (int i = 0; i < deletedCount; i++) {
        widget.socketService.sendText('Backspace');
      }
      HapticFeedback.selectionClick();
    } else if (currentText.length > _previousText.length) {
      int commonPrefix = 0;
      final minLen = math.min(_previousText.length, currentText.length);
      while (commonPrefix < minLen &&
          _previousText[commonPrefix] == currentText[commonPrefix]) {
        commonPrefix++;
      }

      final backspacesNeeded = _previousText.length - commonPrefix;
      for (int i = 0; i < backspacesNeeded; i++) {
        widget.socketService.sendText('Backspace');
      }

      final delta = currentText.substring(commonPrefix);
      if (delta.isNotEmpty) {
        if (delta.contains('\n')) {
          final parts = delta.split('\n');
          for (int i = 0; i < parts.length; i++) {
            if (parts[i].isNotEmpty) {
              widget.socketService.sendText(parts[i]);
            }
            if (i < parts.length - 1) {
              widget.socketService.sendText('Enter');
            }
          }
        } else {
          widget.socketService.sendText(delta);
        }
      }
    }

    if (currentText.length > 64) {
      _resetKeyboardBuffer();
    } else {
      _previousText = currentText;
    }
  }

  // ---------------------------------------------------------------------------
  // Multi-Touch Dot-Matrix Trackpad & Laser Gestures (120Hz Coalesced Pipeline)
  // ---------------------------------------------------------------------------
  void _scheduleNetworkFlush() {
    if (_frameFlushScheduled) return;
    _frameFlushScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frameFlushScheduled = false;
      if (!mounted) return;
      if (_pendingDx != 0.0 || _pendingDy != 0.0) {
        final dx = _pendingDx;
        final dy = _pendingDy;
        _pendingDx = 0.0;
        _pendingDy = 0.0;
        if (_laserModeActive) {
          widget.socketService.sendLaser(active: true, dx: dx, dy: dy);
        } else if (_spotlightModeActive) {
          widget.socketService.sendSpotlight(active: true, dx: dx, dy: dy);
        } else {
          widget.socketService.sendMove(dx, dy);
        }
      }
      if (_pendingScrollDy != 0.0) {
        final sdy = _pendingScrollDy;
        _pendingScrollDy = 0.0;
        widget.socketService.sendScroll(sdy);
      }
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 1) {
      _gestureStartTime = DateTime.now();
      _totalGestureDragDistance = 0.0;
      _maxPointersInGesture = 1;
    } else if (_activePointers.length > _maxPointersInGesture) {
      _maxPointersInGesture = _activePointers.length;
    }

    _touchPointNotifier.value = event.localPosition;
    if (_volumePopoverVisible) {
      setState(() {
        _volumePopoverVisible = false;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    final stepDist = event.delta.distance;
    _totalGestureDragDistance += stepDist;

    // Repaint only the CustomPainter canvas via ValueNotifier (0 widget rebuilds!)
    _touchPointNotifier.value = event.localPosition;

    if (_activePointers.length == 1) {
      // Smooth velocity-based pointer acceleration curve
      final accel = math.min(2.8, 1.45 + stepDist * 0.045);
      _pendingDx += event.delta.dx * accel;
      _pendingDy += event.delta.dy * accel;
      _scheduleNetworkFlush();
    } else if (_activePointers.length >= 2) {
      if (!_presenterLocked && event.delta.dy.abs() > 0.3) {
        _pendingScrollDy += -event.delta.dy * _scrollSensitivity;
        _scheduleNetworkFlush();
      }
    }
  }

  void _onPointerUpOrCancel(int pointerId) {
    _activePointers.remove(pointerId);

    if (_activePointers.isEmpty) {
      final elapsedMs = _gestureStartTime != null
          ? DateTime.now().difference(_gestureStartTime!).inMilliseconds
          : 999;

      if (!_presenterLocked &&
          !_laserModeActive &&
          !_spotlightModeActive &&
          elapsedMs < 260 &&
          _totalGestureDragDistance < 12.0) {
        if (_maxPointersInGesture == 1) {
          HapticFeedback.lightImpact();
          widget.socketService.sendClick('left');
        } else if (_maxPointersInGesture == 2) {
          HapticFeedback.mediumImpact();
          widget.socketService.sendClick('right');
        }
      }

      _touchPointNotifier.value = null;
      _maxPointersInGesture = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Presenter Controls (Laser, Slide, Volume, DND, Lock)
  // ---------------------------------------------------------------------------
  void _toggleLaserPointer({bool? forceState}) {
    final nextState = forceState ?? !_laserModeActive;
    if (nextState == _laserModeActive) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _laserModeActive = nextState;
      if (_laserModeActive && _spotlightModeActive) {
        _spotlightModeActive = false;
        widget.socketService.sendSpotlight(active: false);
      }
    });
    widget.socketService.sendLaser(active: _laserModeActive);
  }

  void _togglePresenterLock() {
    HapticFeedback.mediumImpact();
    setState(() {
      _presenterLocked = !_presenterLocked;
      if (_presenterLocked) {
        _keyboardOverlayVisible = false;
        _volumePopoverVisible = false;
        _keyboardFocusNode.unfocus();
      }
    });
  }

  void _toggleDoNotDisturb() {
    if (_presenterLocked) {
      HapticFeedback.vibrate();
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _dndActive = !_dndActive;
    });
    widget.socketService.sendDnd(_dndActive);
  }

  @override
  Widget build(BuildContext context) {
    final hostName = widget.socketService.connectedHost.isNotEmpty
        ? widget.socketService.connectedHost
        : (widget.socketService.currentPayload?.host ?? 'Laptop');

    return Scaffold(
      backgroundColor: ApirBrand.deepMaroon, // Deep Maroon (#561217)
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // =============================================================
                // 1. TOP STATUS BAR
                // =============================================================
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      // Connection Pill with Royal Blue (#2B62A7) Connected Status Accent
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: ApirBrand.warmCream25,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: _laserModeActive
                                  ? ApirBrand.crimsonRed
                                  : ApirBrand.royalBlue,
                              width: 1.4,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ApirBrand.buildLogoBadge(
                                size: 24,
                                borderRadius: 7,
                                borderColor: _laserModeActive
                                    ? ApirBrand.crimsonRed
                                    : ApirBrand.goldenAmber,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _laserModeActive
                                      ? ApirBrand.crimsonRed
                                      : ApirBrand.royalBlue,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _laserModeActive
                                          ? ApirBrand.crimsonRed
                                          : ApirBrand.royalBlue,
                                      blurRadius: 8,
                                      spreadRadius: 1.5,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'APIR! ',
                                style: ApirBrand.logoHeaderStyle(
                                  fontSize: 12.5,
                                  color: ApirBrand.goldenAmber,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  widget.socketService.isReconnecting
                                      ? 'Reconnecting to $hostName...'
                                      : 'Connected to $hostName',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: ApirBrand.warmCream,
                                    fontFamily: ApirBrand.bodyFontFamily,
                                    fontFamilyFallback: ApirBrand.fontFallbacks,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Presentation Countdown Timer Pill
                      GestureDetector(
                        onTap: _togglePresentationTimer,
                        onLongPress: _cycleTimerPreset,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _timerRunning
                                ? ApirBrand.goldenAmber.withOpacity(0.28)
                                : ApirBrand.warmCream25,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: ApirBrand.goldenAmber,
                              width: 1.2,
                            ),
                          ),
                          child: Text(
                            '⏱ ${_formatTimer(_remainingSeconds)}',
                            style: const TextStyle(
                              color: ApirBrand.goldenAmber,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 6),

                      // Presenter Lock Icon
                      _buildStatusBarIconButton(
                        icon: _presenterLocked
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        tooltip: 'Presenter Lock Mode',
                        isActive: _presenterLocked,
                        activeColor: ApirBrand.goldenAmber,
                        onTap: _togglePresenterLock,
                      ),

                      const SizedBox(width: 6),

                      // Keyboard / Voice Dictation Mic Trigger Icon
                      _buildStatusBarIconButton(
                        icon: Icons.keyboard_voice_rounded,
                        tooltip: 'Remote Keyboard & Voice Dictation',
                        isActive: _keyboardOverlayVisible,
                        activeColor: ApirBrand.royalBlue,
                        onTap: _toggleKeyboardInput,
                      ),

                      const SizedBox(width: 6),

                      // Re-scan / Disconnect Button
                      _buildStatusBarIconButton(
                        icon: Icons.qr_code_scanner_rounded,
                        tooltip: 'Re-scan QR / Disconnect',
                        isActive: false,
                        activeColor: ApirBrand.warmCream,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.socketService.disconnect();
                        },
                      ),
                    ],
                  ),
                ),

                // =============================================================
                // 2. INTERACTIVE DOT-MATRIX TRACKPAD & VIRTUAL LASER (Upper 65%)
                // =============================================================
                Expanded(
                  flex: 65,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _onPointerDown,
                      onPointerMove: _onPointerMove,
                      onPointerUp: (e) => _onPointerUpOrCancel(e.pointer),
                      onPointerCancel: (e) => _onPointerUpOrCancel(e.pointer),
                      child: ValueListenableBuilder<Offset?>(
                        valueListenable: _touchPointNotifier,
                        builder: (context, touchPos, trackpadChild) {
                          return Container(
                            decoration: BoxDecoration(
                              color: ApirBrand.darkMaroonSurface,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: _laserModeActive
                                    ? ApirBrand.crimsonRed
                                    : ((_spotlightModeActive ||
                                            touchPos != null)
                                        ? ApirBrand.goldenAmber
                                        : ApirBrand.warmCream25),
                                width: 1.5,
                              ),
                            ),
                            child: trackpadChild,
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (_slidePreviewActive &&
                                  widget.socketService.latestPreviewBytes !=
                                      null)
                                Opacity(
                                  opacity: 0.38,
                                  child: Image.memory(
                                    widget.socketService.latestPreviewBytes!,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              // Subtle centered official Apir High-Five logo watermark
                              Center(
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: 0.14,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(32),
                                      child: Image.asset(
                                        ApirBrand.logoAssetPath,
                                        width: 140,
                                        height: 140,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              RepaintBoundary(
                                child: CustomPaint(
                                  painter: DotMatrixTrackpadPainter(
                                    touchPointListenable: _touchPointNotifier,
                                    isLaserActive: _laserModeActive,
                                    isLocked: _presenterLocked,
                                  ),
                                ),
                              ),

                              // Subtle watermark status hint in trackpad corner
                              Positioned(
                                left: 18,
                                bottom: 14,
                                right: 18,
                                child: IgnorePointer(
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _laserModeActive
                                            ? 'VIRTUAL LASER POINTER ACTIVE'
                                            : (_spotlightModeActive
                                                ? 'SPOTLIGHT BEAM ACTIVE'
                                                : (_presenterLocked
                                                    ? 'PRESENTER LOCK • CLICKS DISABLED'
                                                    : '1F MOVE/TAP • 2F RIGHT-CLICK/SCROLL')),
                                        style: TextStyle(
                                          color: _laserModeActive
                                              ? ApirBrand.crimsonRed
                                              : ((_spotlightModeActive ||
                                                      _presenterLocked)
                                                  ? ApirBrand.goldenAmber
                                                  : ApirBrand.warmCream
                                                      .withOpacity(0.55)),
                                          fontFamily: ApirBrand.bodyFontFamily,
                                          fontFamilyFallback:
                                              ApirBrand.fontFallbacks,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      if (_dndActive)
                                        const Row(
                                          children: [
                                            Icon(
                                              Icons.nights_stay_rounded,
                                              size: 12,
                                              color: ApirBrand.royalBlue,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'DND ON',
                                              style: TextStyle(
                                                color: ApirBrand.royalBlue,
                                                fontFamily:
                                                    ApirBrand.bodyFontFamily,
                                                fontFamilyFallback:
                                                    ApirBrand.fontFallbacks,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // =============================================================
                // 3. BOTTOM PRESENTER CONTROL DOCK (Lower 35%)
                // =============================================================
                Expanded(
                  flex: 35,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Center Cluster of 3 Circular Utility Buttons:
                        // [Laser Pointer Toggle]  [Volume Control]  [Do Not Disturb]
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            // 1. Laser Pointer Toggle (Hold or Tap) -> Crimson Red (#9E1F36)
                            GestureDetector(
                              onTap: () => _toggleLaserPointer(),
                              onLongPressStart: (_) =>
                                  _toggleLaserPointer(forceState: true),
                              onLongPressEnd: (_) =>
                                  _toggleLaserPointer(forceState: false),
                              child: _buildUtilityCircleButton(
                                icon: Icons.flare_rounded,
                                label: 'Laser',
                                isActive: _laserModeActive,
                                activeColor: ApirBrand.crimsonRed,
                              ),
                            ),

                            // 2. Spotlight Beam Mode -> Golden Amber (#F59E1D)
                            GestureDetector(
                              onTap: _toggleSpotlightMode,
                              child: _buildUtilityCircleButton(
                                icon: Icons.highlight_rounded,
                                label: 'Spotlight',
                                isActive: _spotlightModeActive,
                                activeColor: ApirBrand.goldenAmber,
                              ),
                            ),

                            // 3. Live Slide Thumbnail View -> Royal Blue (#2B62A7)
                            GestureDetector(
                              onTap: _toggleSlidePreview,
                              child: _buildUtilityCircleButton(
                                icon: Icons.slideshow_rounded,
                                label: 'Slide View',
                                isActive: _slidePreviewActive,
                                activeColor: ApirBrand.royalBlue,
                              ),
                            ),

                            // 4. Volume & Presentation Shortcuts -> Golden Amber (#F59E1D)
                            GestureDetector(
                              onTap: () {
                                if (_presenterLocked) {
                                  HapticFeedback.vibrate();
                                  return;
                                }
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _volumePopoverVisible =
                                      !_volumePopoverVisible;
                                });
                              },
                              child: _buildUtilityCircleButton(
                                icon: _isMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_up_rounded,
                                label: 'Volume',
                                isActive: _volumePopoverVisible || _isMuted,
                                activeColor: ApirBrand.goldenAmber,
                              ),
                            ),

                            // 5. Do Not Disturb (Moon Icon) -> Royal Blue (#2B62A7)
                            GestureDetector(
                              onTap: _toggleDoNotDisturb,
                              child: _buildUtilityCircleButton(
                                icon: Icons.nights_stay_rounded,
                                label: 'DND',
                                isActive: _dndActive,
                                activeColor: ApirBrand.royalBlue,
                              ),
                            ),
                          ],
                        ),

                        // Large Circular `<` (Prev Slide) and `>` (Next Slide) Buttons
                        Row(
                          children: [
                            Expanded(
                              child: _buildSlideButton(
                                icon: Icons.chevron_left_rounded,
                                label: 'PREV',
                                isPrimary: false,
                                onTap: () {
                                  HapticFeedback.mediumImpact();
                                  _triggerSlide('prev');
                                },
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 2,
                              child: _buildSlideButton(
                                icon: Icons.chevron_right_rounded,
                                label: 'NEXT SLIDE',
                                isPrimary: true,
                                onTap: () {
                                  HapticFeedback.heavyImpact();
                                  _triggerSlide('next');
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // =================================================================
            // 4. QUICK VOLUME SLIDER & PRESENTATION SHORTCUTS POPOVER
            // =================================================================
            if (_volumePopoverVisible && !_presenterLocked)
              Positioned(
                bottom: 150,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 280,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: ApirBrand.deepMaroon,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: ApirBrand.goldenAmber,
                        width: 1.4,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black87,
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: 'Volume Down',
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _virtualVolumeLevel =
                                      (_virtualVolumeLevel - 0.1)
                                          .clamp(0.0, 1.0);
                                  _isMuted = false;
                                });
                                widget.socketService.sendVolume('down');
                              },
                              icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: ApirBrand.warmCream,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Mute / Unmute',
                              onPressed: () {
                                HapticFeedback.mediumImpact();
                                setState(() {
                                  _isMuted = !_isMuted;
                                });
                                widget.socketService.sendVolume('mute');
                              },
                              icon: Icon(
                                _isMuted
                                    ? Icons.volume_off_rounded
                                    : Icons.volume_mute_rounded,
                                color: _isMuted
                                    ? ApirBrand.crimsonRed
                                    : ApirBrand.goldenAmber,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Volume Up',
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _virtualVolumeLevel =
                                      (_virtualVolumeLevel + 0.1)
                                          .clamp(0.0, 1.0);
                                  _isMuted = false;
                                });
                                widget.socketService.sendVolume('up');
                              },
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                                color: ApirBrand.warmCream,
                              ),
                            ),
                          ],
                        ),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: ApirBrand.goldenAmber,
                            inactiveTrackColor: ApirBrand.warmCream25,
                            thumbColor: ApirBrand.warmCream,
                            overlayColor:
                                ApirBrand.goldenAmber.withOpacity(0.22),
                          ),
                          child: Slider(
                            value: _isMuted ? 0.0 : _virtualVolumeLevel,
                            onChanged: (double newValue) {
                              final delta = newValue - _virtualVolumeLevel;
                              if (delta.abs() >= 0.06) {
                                HapticFeedback.selectionClick();
                                widget.socketService
                                    .sendVolume(delta > 0 ? 'up' : 'down');
                                setState(() {
                                  _virtualVolumeLevel = newValue;
                                  _isMuted = false;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildPresentationActionChip(
                              label: '▶ Start (F5)',
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.socketService.sendPresentation('start');
                                setState(() => _volumePopoverVisible = false);
                              },
                            ),
                            _buildPresentationActionChip(
                              label: '⬛ Blackout',
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.socketService
                                    .sendPresentation('blackout');
                              },
                            ),
                            _buildPresentationActionChip(
                              label: '⏹ Exit (Esc)',
                              onTap: () {
                                HapticFeedback.mediumImpact();
                                widget.socketService.sendPresentation('esc');
                                setState(() => _volumePopoverVisible = false);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // =================================================================
            // 5. HIDDEN / OVERLAY TEXTFIELD FOR REMOTE KEYBOARD & DICTATION
            // =================================================================
            Positioned(
              left: 16,
              right: 16,
              top: 62,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                offset: _keyboardOverlayVisible
                    ? Offset.zero
                    : const Offset(0, -2.5),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _keyboardOverlayVisible ? 1.0 : 0.0,
                  child: IgnorePointer(
                    ignoring: !_keyboardOverlayVisible,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ApirBrand.deepMaroon.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: ApirBrand.goldenAmber,
                          width: 1.4,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mic_none_rounded,
                            color: ApirBrand.goldenAmber,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _keyboardController,
                              focusNode: _keyboardFocusNode,
                              autofocus: false,
                              enableSuggestions: true,
                              autocorrect: true,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              style: const TextStyle(
                                color: ApirBrand.warmCream,
                                fontFamily: ApirBrand.bodyFontFamily,
                                fontFamilyFallback: ApirBrand.fontFallbacks,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText:
                                    'Type or use keyboard mic to dictate to laptop...',
                                hintStyle: TextStyle(
                                  color: ApirBrand.warmCream.withOpacity(0.55),
                                  fontFamily: ApirBrand.bodyFontFamily,
                                  fontFamilyFallback: ApirBrand.fontFallbacks,
                                  fontSize: 13,
                                ),
                              ),
                              onChanged: _onRemoteTextChanged,
                              onSubmitted: (_) {
                                widget.socketService.sendText('Enter');
                                _resetKeyboardBuffer();
                              },
                            ),
                          ),
                          IconButton(
                            tooltip: 'Send Enter',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.socketService.sendText('Enter');
                            },
                            icon: const Icon(
                              Icons.keyboard_return_rounded,
                              color: ApirBrand.goldenAmber,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Backspace',
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              widget.socketService.sendText('Backspace');
                            },
                            icon: const Icon(
                              Icons.backspace_outlined,
                              color: ApirBrand.warmCream,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresentationActionChip({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: ApirBrand.warmCream25,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ApirBrand.goldenAmber, width: 1.0),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: ApirBrand.warmCream,
            fontFamily: ApirBrand.bodyFontFamily,
            fontFamilyFallback: ApirBrand.fontFallbacks,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBarIconButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withOpacity(0.25)
                : ApirBrand.warmCream25,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? activeColor : ApirBrand.warmCream25,
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? activeColor : ApirBrand.warmCream,
          ),
        ),
      ),
    );
  }

  Widget _buildUtilityCircleButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: isActive
                ? activeColor.withOpacity(0.28)
                : ApirBrand.warmCream25,
            shape: BoxShape.circle,
            border: Border.all(
              color: isActive ? activeColor : ApirBrand.warmCream25,
              width: isActive ? 1.8 : 1.2,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.50),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            color: isActive ? activeColor : ApirBrand.warmCream,
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: isActive
                ? activeColor
                : ApirBrand.warmCream.withOpacity(0.80),
            fontFamily: ApirBrand.bodyFontFamily,
            fontFamilyFallback: ApirBrand.fontFallbacks,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSlideButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    final accent = isPrimary ? ApirBrand.goldenAmber : ApirBrand.warmCream;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(44),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: isPrimary
                ? ApirBrand.goldenAmber
                : ApirBrand.warmCream25,
            borderRadius: BorderRadius.circular(44),
            border: Border.all(
              color: isPrimary
                  ? ApirBrand.goldenAmber
                  : ApirBrand.warmCream.withOpacity(0.45),
              width: 1.5,
            ),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: ApirBrand.goldenAmber.withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isPrimary) Icon(icon, color: accent, size: 30),
              Text(
                label,
                style: TextStyle(
                  color:
                      isPrimary ? ApirBrand.deepMaroon : ApirBrand.warmCream,
                  fontFamily: ApirBrand.bodyFontFamily,
                  fontFamilyFallback: ApirBrand.fontFallbacks,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              if (isPrimary) ...[
                const SizedBox(width: 6),
                Icon(icon, color: ApirBrand.deepMaroon, size: 32),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// CustomPainter rendering the responsive grid of Warm Cream (`#FDECC8` at 25%
/// opacity) inactive trackpad dots that dynamically scale and glow GOLDEN AMBER
/// (`#F59E1D`) around the user's touch point during cursor movement, or glow
/// CRIMSON RED (`#9E1F36`) when Virtual Laser Pointer mode is active.
class DotMatrixTrackpadPainter extends CustomPainter {
  final ValueListenable<Offset?> touchPointListenable;
  final bool isLaserActive;
  final bool isLocked;

  DotMatrixTrackpadPainter({
    required this.touchPointListenable,
    required this.isLaserActive,
    required this.isLocked,
  }) : super(repaint: touchPointListenable);

  @override
  void paint(Canvas canvas, Size size) {
    const double spacing = 24.0;
    const double baseRadius = 1.75;
    const double influenceRadius = 115.0;
    const double influenceRadiusSq = influenceRadius * influenceRadius;
    final Offset? touchPoint = touchPointListenable.value;

    // Active Laser Mode Glow: Crimson Red (#9E1F36)
    // Primary Accent & Normal Trackpad Glow: Golden Amber (#F59E1D)
    final Color activeGlowColor =
        isLaserActive ? ApirBrand.crimsonRed : ApirBrand.goldenAmber;

    // Inactive Trackpad Dots: Warm Cream (#FDECC8 at 25% opacity)
    const Color baseDotColor = ApirBrand.warmCream25;

    final Paint basePaint = Paint()
      ..color = baseDotColor
      ..style = PaintingStyle.fill;
    final Paint activeDotPaint = Paint()..style = PaintingStyle.fill;
    final Paint glowPaint = Paint()..style = PaintingStyle.fill;

    // Ambient radial halo around active touch point
    if (touchPoint != null) {
      final Rect haloRect =
          Rect.fromCircle(center: touchPoint, radius: influenceRadius);
      final Paint haloPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            activeGlowColor.withOpacity(isLaserActive ? 0.36 : 0.26),
            activeGlowColor.withOpacity(0.0),
          ],
        ).createShader(haloRect);
      canvas.drawCircle(touchPoint, influenceRadius, haloPaint);
    }

    final int cols = (size.width / spacing).floor();
    final int rows = (size.height / spacing).floor();
    final double startX = (size.width - (cols - 1) * spacing) / 2.0;
    final double startY = (size.height - (rows - 1) * spacing) / 2.0;

    for (int r = 0; r < rows; r++) {
      final double y = startY + r * spacing;
      for (int c = 0; c < cols; c++) {
        final double x = startX + c * spacing;
        final Offset dotCenter = Offset(x, y);

        if (touchPoint == null) {
          canvas.drawCircle(dotCenter, baseRadius, basePaint);
          continue;
        }

        final double dx = x - touchPoint.dx;
        final double dy = y - touchPoint.dy;
        final double distSq = dx * dx + dy * dy;
        if (distSq >= influenceRadiusSq) {
          canvas.drawCircle(dotCenter, baseRadius, basePaint);
        } else {
          final double dist = math.sqrt(distSq);
          // Smooth falloff curve (0.0 at edge -> 1.0 at touch center)
          final double t = 1.0 - (dist / influenceRadius);
          final double eased = t * t * (3.0 - 2.0 * t);
          final double radius = baseRadius + 3.4 * eased;

          if (eased > 0.35) {
            glowPaint.color = activeGlowColor.withOpacity(0.28 * eased);
            canvas.drawCircle(dotCenter, radius * 1.65, glowPaint);
          }

          activeDotPaint.color =
              Color.lerp(baseDotColor, activeGlowColor, eased)!;
          canvas.drawCircle(dotCenter, radius, activeDotPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotMatrixTrackpadPainter oldDelegate) {
    return oldDelegate.touchPointListenable != touchPointListenable ||
        oldDelegate.isLaserActive != isLaserActive ||
        oldDelegate.isLocked != isLocked;
  }
}
