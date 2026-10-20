import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models/pairing_payload.dart';
import '../services/apir_socket_service.dart';

/// Home screen featuring the Deep Maroon (`#561217`) cultural brand palette,
/// `Tribo` header wordmark ("APIR"), QR camera viewfinder with a Golden Amber
/// (`#F59E1D`) glowing rounded-square overlay, 1-tap last-host reconnection
/// accented in Royal Blue (`#2B62A7`), and a "Manual IP Entry" bottom sheet.
class ScannerScreen extends StatefulWidget {
  final ApirSocketService socketService;

  const ScannerScreen({
    super.key,
    required this.socketService,
  });

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  late final AnimationController _glowController;
  bool _isProcessingCode = false;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleRawBarcode(String? rawValue) async {
    if (rawValue == null || _isProcessingCode) return;

    final payload = PairingPayload.tryParseRaw(rawValue);
    if (payload == null) return;

    setState(() => _isProcessingCode = true);
    HapticFeedback.selectionClick();

    final ok = await widget.socketService.connectAndHandshake(payload);
    if (!mounted) return;

    if (!ok) {
      final err = widget.socketService.errorMessage ?? 'Handshake failed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ApirBrand.crimsonRed,
          content: Text(
            err,
            style: const TextStyle(
              color: ApirBrand.warmCream,
              fontFamily: ApirBrand.bodyFontFamily,
              fontFamilyFallback: ApirBrand.fontFallbacks,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() => _isProcessingCode = false);
      }
    }
  }

  Future<void> _reconnectSavedHost(PairingPayload saved) async {
    if (_isProcessingCode) return;
    setState(() => _isProcessingCode = true);
    HapticFeedback.lightImpact();

    final ok = await widget.socketService.connectAndHandshake(saved);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ApirBrand.crimsonRed,
          content: Text(
            widget.socketService.errorMessage ??
                'Could not reconnect to ${saved.host}. Scan new QR if PIN changed.',
            style: const TextStyle(
              color: ApirBrand.warmCream,
              fontFamily: ApirBrand.bodyFontFamily,
              fontFamilyFallback: ApirBrand.fontFallbacks,
            ),
          ),
        ),
      );
      setState(() => _isProcessingCode = false);
    }
  }

  void _openManualEntrySheet() {
    HapticFeedback.lightImpact();
    final saved = widget.socketService.lastSavedPayload;
    String defaultIp = '192.168.1.';
    String defaultPort = '8765';
    if (saved != null) {
      final uri = Uri.tryParse(saved.uri);
      if (uri != null && uri.host.isNotEmpty) {
        defaultIp = uri.host;
        if (uri.hasPort) defaultPort = uri.port.toString();
      }
    }

    final ipCtrl = TextEditingController(text: defaultIp);
    final portCtrl = TextEditingController(text: defaultPort);
    final hostCtrl = TextEditingController(text: saved?.host ?? 'Laptop');
    final pinCtrl = TextEditingController(text: saved?.token ?? '');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ApirBrand.deepMaroon,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: ApirBrand.goldenAmber, width: 1.2),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'MANUAL IP PAIRING',
                    style: ApirBrand.logoHeaderStyle(
                      fontSize: 18,
                      color: ApirBrand.goldenAmber,
                      letterSpacing: 1.8,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(
                      Icons.close,
                      color: ApirBrand.warmCream,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildBrandTextField(
                      controller: ipCtrl,
                      label: 'Laptop LAN IPv4',
                      hint: '192.168.1.10',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: _buildBrandTextField(
                      controller: portCtrl,
                      label: 'Port',
                      hint: '8765',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildBrandTextField(
                      controller: pinCtrl,
                      label: '4-Digit Session PIN',
                      hint: '4829',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildBrandTextField(
                      controller: hostCtrl,
                      label: 'Host Label',
                      hint: 'My Laptop',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ApirBrand.goldenAmber,
                  foregroundColor: ApirBrand.deepMaroon,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () async {
                  final ip = ipCtrl.text.trim();
                  final port = portCtrl.text.trim().isEmpty
                      ? '8765'
                      : portCtrl.text.trim();
                  final pin = pinCtrl.text.trim();
                  final host = hostCtrl.text.trim().isEmpty
                      ? ip
                      : hostCtrl.text.trim();
                  if (ip.isEmpty || pin.isEmpty) return;

                  Navigator.of(ctx).pop();
                  final manualPayload = PairingPayload(
                    app: 'apir',
                    uri: 'ws://$ip:$port',
                    host: host,
                    token: pin,
                  );
                  await _reconnectSavedHost(manualPayload);
                },
                icon: const Icon(Icons.bolt_rounded),
                label: const Text(
                  'Connect & Handshake',
                  style: TextStyle(
                    fontFamily: ApirBrand.bodyFontFamily,
                    fontFamilyFallback: ApirBrand.fontFallbacks,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBrandTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: ApirBrand.warmCream,
        fontFamily: ApirBrand.bodyFontFamily,
        fontFamilyFallback: ApirBrand.fontFallbacks,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(
          color: ApirBrand.warmCream.withOpacity(0.75),
          fontSize: 12,
        ),
        hintStyle: const TextStyle(color: ApirBrand.warmCream25),
        filled: true,
        fillColor: ApirBrand.warmCream25,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: ApirBrand.warmCream25),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: ApirBrand.goldenAmber, width: 1.6),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savedHost = widget.socketService.lastSavedPayload;

    return Scaffold(
      backgroundColor: ApirBrand.deepMaroon,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header with Tribo Wordmark ("APIR")
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      ApirBrand.buildLogoBadge(
                        size: 38,
                        borderRadius: 11,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'APIR',
                        style: ApirBrand.logoHeaderStyle(
                          fontSize: 24,
                          color: ApirBrand.goldenAmber,
                          letterSpacing: 3.5,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: ApirBrand.warmCream25,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ApirBrand.goldenAmber.withOpacity(0.5),
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Toggle Torch',
                      onPressed: () => _scannerController.toggleTorch(),
                      icon: const Icon(
                        Icons.flashlight_on_outlined,
                        color: ApirBrand.warmCream,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Scan the QR code displayed on your laptop to high-five & pair.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ApirBrand.warmCream.withOpacity(0.85),
                  fontFamily: ApirBrand.bodyFontFamily,
                  fontFamilyFallback: ApirBrand.fontFallbacks,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Camera Viewfinder with Golden Amber Glowing Rounded-Square Overlay
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: (BarcodeCapture capture) {
                          for (final barcode in capture.barcodes) {
                            if (barcode.rawValue != null) {
                              _handleRawBarcode(barcode.rawValue);
                              break;
                            }
                          }
                        },
                      ),

                      // Custom Glowing Rounded Square Viewfinder Overlay
                      AnimatedBuilder(
                        animation: _glowController,
                        builder: (context, _) {
                          return CustomPaint(
                            painter: GlowingScannerOverlayPainter(
                              pulseValue: _glowController.value,
                              isConnecting:
                                  widget.socketService.isConnecting ||
                                      _isProcessingCode,
                            ),
                          );
                        },
                      ),

                      if (widget.socketService.isConnecting ||
                          _isProcessingCode)
                        Container(
                          color: ApirBrand.deepMaroon.withOpacity(0.82),
                          alignment: Alignment.center,
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: ApirBrand.goldenAmber,
                              ),
                              SizedBox(height: 14),
                              Text(
                                'Apir! Completing Handshake...',
                                style: TextStyle(
                                  color: ApirBrand.goldenAmber,
                                  fontFamily: ApirBrand.bodyFontFamily,
                                  fontFamilyFallback: ApirBrand.fontFallbacks,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // 1-Tap Instant Reconnect Card (Warm Cream 25% surface + Royal Blue tech accent)
            if (savedHost != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _reconnectSavedHost(savedHost),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: ApirBrand.warmCream25,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: ApirBrand.royalBlue,
                        width: 1.4,
                      ),
                    ),
                    child: Row(
                      children: [
                        ApirBrand.buildLogoBadge(
                          size: 40,
                          borderRadius: 12,
                          borderColor: ApirBrand.royalBlue,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reconnect to ${savedHost.host}',
                                style: const TextStyle(
                                  color: ApirBrand.warmCream,
                                  fontFamily: ApirBrand.bodyFontFamily,
                                  fontFamilyFallback: ApirBrand.fontFallbacks,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${savedHost.uri} • 1-Tap Instant Pair',
                                style: TextStyle(
                                  color: ApirBrand.warmCream.withOpacity(0.75),
                                  fontFamily: ApirBrand.bodyFontFamily,
                                  fontFamilyFallback: ApirBrand.fontFallbacks,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: ApirBrand.goldenAmber,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Manual IP Entry Button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: TextButton.icon(
                onPressed: _openManualEntrySheet,
                icon: const Icon(
                  Icons.keyboard_alt_outlined,
                  color: ApirBrand.goldenAmber,
                  size: 18,
                ),
                label: const Text(
                  'Manual IP Entry',
                  style: TextStyle(
                    color: ApirBrand.goldenAmber,
                    fontFamily: ApirBrand.bodyFontFamily,
                    fontFamilyFallback: ApirBrand.fontFallbacks,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CustomPainter drawing a Deep Maroon vignette mask and a glowing Golden Amber
/// (`#F59E1D`) or Royal Blue (`#2B62A7` when connecting) rounded square viewfinder.
class GlowingScannerOverlayPainter extends CustomPainter {
  final double pulseValue;
  final bool isConnecting;

  GlowingScannerOverlayPainter({
    required this.pulseValue,
    required this.isConnecting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cutoutSize = (size.shortestSide * 0.68).clamp(180.0, 280.0);
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutoutSize,
      height: cutoutSize,
    );
    final rrect = RRect.fromRectAndRadius(
      cutoutRect,
      const Radius.circular(28),
    );

    // 1. Deep Maroon translucent surround mask
    final overlayPath = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = ApirBrand.deepMaroon.withOpacity(0.76),
    );

    // 2. Outer ambient Golden Amber / Royal Blue glow
    final glowColor =
        isConnecting ? ApirBrand.royalBlue : ApirBrand.goldenAmber;
    final glowPaint = Paint()
      ..color = glowColor.withOpacity(0.32 + 0.34 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0 + 4.0 * pulseValue
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    canvas.drawRRect(rrect, glowPaint);

    // 3. Crisp glowing rounded square border
    final borderPaint = Paint()
      ..color = glowColor.withOpacity(0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6;

    canvas.drawRRect(rrect, borderPaint);

    // 4. Animated horizontal scan line inside the rounded square
    final scanY =
        cutoutRect.top + 24 + (cutoutRect.height - 48) * pulseValue;
    final scanRect = Rect.fromLTWH(
      cutoutRect.left + 20,
      scanY,
      cutoutRect.width - 40,
      2.2,
    );
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          glowColor.withOpacity(0.0),
          glowColor.withOpacity(0.90),
          glowColor.withOpacity(0.0),
        ],
      ).createShader(scanRect);

    canvas.drawRect(scanRect, scanPaint);
  }

  @override
  bool shouldRepaint(covariant GlowingScannerOverlayPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.isConnecting != isConnecting;
  }
}
