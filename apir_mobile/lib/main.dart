import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/controller_screen.dart';
import 'screens/scanner_screen.dart';
import 'services/apir_socket_service.dart';

/// Official Apir Cultural Brand Identity Palette & Typography Constants
class ApirBrand {
  /// Scaffold / Background Color: Deep Maroon (`#561217`)
  static const Color deepMaroon = Color(0xFF561217);

  /// Darker Maroon shade for elevated cards/borders (`#3D0C10`)
  static const Color darkMaroonSurface = Color(0xFF3D0C10);

  /// Primary Accent & Normal Trackpad Glow: Golden Amber (`#F59E1D`)
  static const Color goldenAmber = Color(0xFFF59E1D);

  /// Warm Cream full opacity (`#FDECC8`) for high-contrast text
  static const Color warmCream = Color(0xFFFDECC8);

  /// Secondary Surface & Inactive Trackpad Dots: Warm Cream (`#FDECC8` at 25% opacity)
  static const Color warmCream25 = Color(0x40FDECC8);

  /// Active Laser Mode Glow: Crimson Red (`#9E1F36`)
  static const Color crimsonRed = Color(0xFF9E1F36);

  /// Secondary Tech / Connected Status Accent: Royal Blue (`#2B62A7`)
  static const Color royalBlue = Color(0xFF2B62A7);

  /// Official Cultural Brand High-Five Logo Asset
  static const String logoAssetPath = 'assets/images/apir_logo.png';

  /// Header / Logo Font Family (`Tribo` with fallback to `Montserrat` / `Plus Jakarta Sans`)
  static const String headerFontFamily = 'Tribo';

  /// Default Body & Button Font Family (`Garet` with fallback to `Montserrat` / `Plus Jakarta Sans`)
  static const String bodyFontFamily = 'Garet';

  static const List<String> fontFallbacks = <String>[
    'Montserrat',
    'Plus Jakarta Sans',
    'sans-serif',
  ];

  static Widget buildLogoBadge({
    double size = 34,
    double borderRadius = 10,
    Color borderColor = goldenAmber,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: goldenAmber.withOpacity(0.32),
            blurRadius: 8,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1.2),
        child: Image.asset(
          logoAssetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  static TextStyle logoHeaderStyle({
    double fontSize = 24,
    Color color = goldenAmber,
    double letterSpacing = 3.0,
  }) {
    return TextStyle(
      fontFamily: headerFontFamily,
      fontFamilyFallback: fontFallbacks,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock presenter controller to portrait and style system bars with Deep Maroon
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: ApirBrand.deepMaroon,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ApirRemoteApp());
}

class ApirRemoteApp extends StatefulWidget {
  const ApirRemoteApp({super.key});

  @override
  State<ApirRemoteApp> createState() => _ApirRemoteAppState();
}

class _ApirRemoteAppState extends State<ApirRemoteApp> {
  late final ApirSocketService _socketService;

  @override
  void initState() {
    super.initState();
    _socketService = ApirSocketService();
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = ThemeData.dark().textTheme.apply(
          fontFamily: ApirBrand.bodyFontFamily,
          fontFamilyFallback: ApirBrand.fontFallbacks,
          bodyColor: ApirBrand.warmCream,
          displayColor: ApirBrand.warmCream,
        );

    return MaterialApp(
      title: 'Apir Remote',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ApirBrand.deepMaroon,
        fontFamily: ApirBrand.bodyFontFamily,
        fontFamilyFallback: ApirBrand.fontFallbacks,
        colorScheme: const ColorScheme.dark(
          primary: ApirBrand.goldenAmber,
          onPrimary: ApirBrand.deepMaroon,
          secondary: ApirBrand.royalBlue,
          onSecondary: ApirBrand.warmCream,
          tertiary: ApirBrand.crimsonRed,
          surface: ApirBrand.warmCream25,
          onSurface: ApirBrand.warmCream,
          error: ApirBrand.crimsonRed,
        ),
        textTheme: baseTextTheme.copyWith(
          displayLarge: ApirBrand.logoHeaderStyle(fontSize: 32),
          displayMedium: ApirBrand.logoHeaderStyle(fontSize: 26),
          headlineLarge: ApirBrand.logoHeaderStyle(fontSize: 24),
          headlineMedium: ApirBrand.logoHeaderStyle(fontSize: 20),
          titleLarge: ApirBrand.logoHeaderStyle(fontSize: 18, letterSpacing: 1.8),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: ApirBrand.goldenAmber,
            foregroundColor: ApirBrand.deepMaroon,
            textStyle: const TextStyle(
              fontFamily: ApirBrand.bodyFontFamily,
              fontFamilyFallback: ApirBrand.fontFallbacks,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: ApirBrand.goldenAmber,
            textStyle: const TextStyle(
              fontFamily: ApirBrand.bodyFontFamily,
              fontFamilyFallback: ApirBrand.fontFallbacks,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: AnimatedBuilder(
        animation: _socketService,
        builder: (context, _) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: _socketService.isConnected
                ? ControllerScreen(
                    key: const ValueKey('apir_controller_screen'),
                    socketService: _socketService,
                  )
                : ScannerScreen(
                    key: const ValueKey('apir_scanner_screen'),
                    socketService: _socketService,
                  ),
          );
        },
      ),
    );
  }
}
