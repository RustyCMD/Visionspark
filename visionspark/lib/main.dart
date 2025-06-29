import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'shared/offline_screen.dart';
import 'shared/connectivity_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your project's widgets
import 'auth/auth_gate.dart';
import 'shared/notifiers/subscription_status_notifier.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Custom theme controller
class ThemeController extends ChangeNotifier {
  bool _isDarkMode = true;
  bool get isDarkMode => _isDarkMode;

  ThemeController() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // Initialize deep link handling
  _initDeepLinks();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
      ],
      child: const MyApp(),
    ),
  );
}

StreamSubscription? _sub;
AppLinks? _appLinks;

/// Initializes the deep link listener to manually handle the auth callback.
void _initDeepLinks() {
  _appLinks = AppLinks();
  _sub = _appLinks!.uriLinkStream.listen((Uri? uri) {
    if (uri != null) {
      debugPrint("Deep link received: $uri");
      // Check if this is the password recovery callback
      if (uri.queryParameters.containsKey('token') &&
          uri.queryParameters['type'] == 'recovery') {
        final authCode = uri.queryParameters['token']!;
        debugPrint("Found PKCE token. Exchanging for session...");
        
        // Manually exchange the code for a session.
        // This will trigger the onAuthStateChange stream with the
        // passwordRecovery event, which AuthGate will then handle.
        Supabase.instance.client.auth.exchangeCodeForSession(authCode);
      }
    }
  }, onError: (err) {
    debugPrint("Error listening to deep links: $err");
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);

    // New VisionSpark Color Palette
    const Color vsPrimaryIndigo = Color(0xFF3949AB); // Primary
    const Color vsSecondaryTeal = Color(0xFF00ACC1); // Secondary
    // const Color vsAccentAmber = Color(0xFFFFB300); // Accent - will be used strategically

    // Light Theme ColorScheme
    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: vsPrimaryIndigo,
      onPrimary: Colors.white,
      secondary: vsSecondaryTeal,
      onSecondary: Colors.black, // For high contrast on Teal
      surface: const Color(0xFFF5F5F5), // Light grey for surfaces
      onSurface: const Color(0xFF212121), // Dark grey for text on light surfaces
      background: Colors.white, // Clean white background
      onBackground: const Color(0xFF212121), // Dark grey for text on white background
      error: const Color(0xFFD32F2F), // Standard error red
      onError: Colors.white,
      // Optional: Define tertiary if needed, or use vsAccentAmber directly
      // tertiary: vsAccentAmber,
      // onTertiary: Colors.black,
    );

    // Dark Theme ColorScheme
    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: const Color(0xFF7986CB), // Lighter Indigo for dark theme
      onPrimary: Colors.black, // Black text on lighter Indigo
      secondary: const Color(0xFF4DD0E1), // Lighter Teal for dark theme
      onSecondary: Colors.black, // Black text on lighter Teal
      surface: const Color(0xFF212121), // Dark grey for surfaces
      onSurface: Colors.white, // White text on dark surfaces
      background: const Color(0xFF121212), // Standard dark theme background
      onBackground: Colors.white, // White text on dark background
      error: const Color(0xFFEF9A9A), // Lighter error red for dark theme
      onError: Colors.black,
      // Optional: Define tertiary if needed
      // tertiary: vsAccentAmber, // Amber might need adjustment for dark theme if used as tertiary
      // onTertiary: Colors.black,
    );

    return StreamBuilder<bool>(
      stream: ConnectivityService().onStatusChange,
      initialData: ConnectivityService().isOnline,
      builder: (context, snapshot) {
        final isOnline = snapshot.data ?? true;
        if (!isOnline) {
          return MaterialApp(
            home: OfflineScreen(
              onRetry: () => ConnectivityService().retryCheck(),
            ),
            debugShowCheckedModeBanner: false,
          );
        }
        return MaterialApp(
          title: 'Visionspark',
          navigatorKey: navigatorKey,
          theme: _buildTheme(lightScheme),
          darkTheme: _buildTheme(darkScheme),
          themeMode: themeController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AuthGate(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

ThemeData _buildTheme(ColorScheme colorScheme) {
  return ThemeData.from(colorScheme: colorScheme, useMaterial3: true).copyWith(
    cardTheme: CardTheme(
      elevation: 2, // Default elevation for cards
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0), // Consistent border radius
      ),
      // In M3, Card color defaults to surface. If we want a different default:
      // color: colorScheme.surfaceContainerLow, // Example: slightly off-surface
      // However, explicit coloring on cards per-screen might be better for flexibility.
      // For now, let's rely on local Card color settings if a deviation from `surface` is needed.
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainer, // M3 standard fill color
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0), // Consistent border radius
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: colorScheme.primary, width: 2.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: colorScheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: BorderSide(color: colorScheme.error, width: 2.0),
      ),
    ),
    // Example: If all ElevatedButtons should have a specific padding or shape
    // elevatedButtonTheme: ElevatedButtonThemeData(
    //   style: ElevatedButton.styleFrom(
    //     padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    //     shape: RoundedRectangleBorder(
    //       borderRadius: BorderRadius.circular(12.0),
    //     ),
    //   ),
    // ),
  );
}

// AuthGate has been moved to lib/auth/auth_gate.dart
// AuthScreen has been moved to lib/auth/auth_screen.dart
// MainScaffold has been moved to lib/shared/main_scaffold.dart
// ImageGeneratorScreen has been moved to lib/features/image_generator/image_generator_screen.dart
// AccountSection has been moved to lib/features/account/account_section.dart
