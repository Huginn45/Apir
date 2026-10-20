import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/pairing_payload.dart';

/// Manages the low-latency WebSocket connection, QR PIN handshake,
/// last-host persistence, and real-time presenter command streaming.
class ApirSocketService extends ChangeNotifier {
  static const String _prefLastHostKey = 'apir_last_pairing_payload';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  PairingPayload? _currentPayload;
  PairingPayload? _lastSavedPayload;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _errorMessage;
  String _connectedHost = '';
  Uint8List? _latestPreviewBytes;

  PairingPayload? get currentPayload => _currentPayload;
  PairingPayload? get lastSavedPayload => _lastSavedPayload;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get errorMessage => _errorMessage;
  String get connectedHost => _connectedHost;
  Uint8List? get latestPreviewBytes => _latestPreviewBytes;

  ApirSocketService() {
    loadSavedHost();
  }

  /// Load the last paired host from `shared_preferences` for 1-tap reconnection.
  Future<void> loadSavedHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefLastHostKey);
      if (raw != null && raw.isNotEmpty) {
        _lastSavedPayload = PairingPayload.tryParseRaw(raw);
        notifyListeners();
      }
    } catch (_) {
      // Ignore storage read errors gracefully
    }
  }

  Future<void> _saveHost(PairingPayload payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastHostKey, payload.toRawJson());
      _lastSavedPayload = payload;
    } catch (_) {
      // Ignore storage write errors gracefully
    }
  }

  /// Perform the "Apir Handshake" with the desktop server:
  /// 1. Connect to `ws://<local_ip>:8765`
  /// 2. Send `{"type": "handshake", "token": "<4_digit_pin>"}`
  /// 3. Wait for `handshake_ack` with status `ok`
  /// 4. Trigger `HapticFeedback.heavyImpact()` ("Apir!")
  Future<bool> connectAndHandshake(PairingPayload payload) async {
    await disconnect(notify: false);

    _isConnecting = true;
    _errorMessage = null;
    _currentPayload = payload;
    notifyListeners();

    final completer = Completer<bool>();

    try {
      final wsUri = Uri.parse(payload.uri);
      final channel = WebSocketChannel.connect(wsUri);
      _channel = channel;

      await channel.ready.timeout(const Duration(seconds: 4));

      _subscription = channel.stream.listen(
        (dynamic rawMsg) {
          try {
            final Map<String, dynamic> data =
                jsonDecode(rawMsg.toString()) as Map<String, dynamic>;
            final type = data['type'];

            if (type == 'handshake_ack') {
              if (data['status'] == 'ok') {
                _isConnected = true;
                _isConnecting = false;
                _connectedHost = (data['host'] ?? payload.host).toString();
                _errorMessage = null;

                // Trigger signature "Apir!" High-Five Heavy Haptic Impact
                HapticFeedback.heavyImpact();
                _saveHost(payload);
                notifyListeners();

                if (!completer.isCompleted) {
                  completer.complete(true);
                }
              } else {
                _errorMessage =
                    (data['message'] ?? 'Invalid session PIN token').toString();
                _isConnected = false;
                _isConnecting = false;
                notifyListeners();

                if (!completer.isCompleted) {
                  completer.complete(false);
                }
                disconnect();
              }
            } else if (type == 'preview_frame' && data['image'] != null) {
              _latestPreviewBytes = base64Decode(data['image'].toString());
              notifyListeners();
            }
          } catch (_) {
            // Ignore non-JSON frames
          }
        },
        onError: (Object error) {
          _errorMessage = 'Connection error: $error';
          _isConnected = false;
          _isConnecting = false;
          notifyListeners();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
        onDone: () {
          _isConnected = false;
          _isConnecting = false;
          notifyListeners();
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        },
      );

      // Dispatch QR Pairing Handshake message
      _sendRaw({
        'type': 'handshake',
        'token': payload.token,
      });

      return await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          _errorMessage = 'Handshake timed out waiting for desktop response.';
          _isConnected = false;
          _isConnecting = false;
          notifyListeners();
          disconnect();
          return false;
        },
      );
    } catch (e) {
      _errorMessage = 'Could not reach ${payload.uri}';
      _isConnected = false;
      _isConnecting = false;
      notifyListeners();
      await disconnect(notify: false);
      return false;
    }
  }

  void _sendRaw(Map<String, dynamic> payload) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  /// Slide navigation (`next` | `prev`)
  void sendSlide(String dir) {
    if (!_isConnected) return;
    _sendRaw({'type': 'slide', 'dir': dir});
  }

  /// Relative mouse cursor movement (`dx`, `dy`)
  void sendMove(double dx, double dy) {
    if (!_isConnected) return;
    _sendRaw({
      'type': 'move',
      'dx': double.parse(dx.toStringAsFixed(2)),
      'dy': double.parse(dy.toStringAsFixed(2)),
    });
  }

  /// Mouse click (`left` | `right`)
  void sendClick(String button) {
    if (!_isConnected) return;
    _sendRaw({'type': 'click', 'button': button});
  }

  /// Vertical 2-finger scroll (`dy`)
  void sendScroll(double dy) {
    if (!_isConnected) return;
    _sendRaw({
      'type': 'scroll',
      'dy': double.parse(dy.toStringAsFixed(2)),
    });
  }

  /// System media volume (`up` | `down` | `mute`)
  void sendVolume(String action) {
    if (!_isConnected) return;
    _sendRaw({'type': 'volume', 'action': action});
  }

  /// Real-time keyboard & voice dictation character/key streaming
  void sendText(String value) {
    if (!_isConnected || value.isEmpty) return;
    _sendRaw({'type': 'text', 'value': value});
  }

  /// Virtual red laser pointer overlay control
  void sendLaser({required bool active, double dx = 0.0, double dy = 0.0}) {
    if (!_isConnected) return;
    _sendRaw({
      'type': 'laser',
      'active': active,
      'dx': double.parse(dx.toStringAsFixed(2)),
      'dy': double.parse(dy.toStringAsFixed(2)),
    });
  }

  /// Fullscreen Spotlight beam overlay control
  void sendSpotlight({required bool active, double dx = 0.0, double dy = 0.0}) {
    if (!_isConnected) return;
    _sendRaw({
      'type': 'spotlight',
      'active': active,
      'dx': double.parse(dx.toStringAsFixed(2)),
      'dy': double.parse(dy.toStringAsFixed(2)),
    });
  }

  /// Presentation shortcut commands (`start` F5 | `blackout` B | `esc` Esc)
  void sendPresentation(String action) {
    if (!_isConnected) return;
    _sendRaw({'type': 'presentation', 'action': action});
  }

  /// Request a compressed JPEG slide thumbnail from the desktop screen
  void requestPreview() {
    if (!_isConnected) return;
    _sendRaw({'type': 'request_preview'});
  }

  /// Toggle laptop Do Not Disturb / Focus Assist
  void sendDnd(bool active) {
    if (!_isConnected) return;
    _sendRaw({'type': 'dnd', 'active': active});
  }

  Future<void> disconnect({bool notify = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disconnect(notify: false);
    super.dispose();
  }
}
