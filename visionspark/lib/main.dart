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
    const Color lilacPurple = Color(0xFFD0B8E1);
    const Color softTeal = Color(0xFF87CEEB);
    const Color mutedPeach = Color(0xFFFFDAB9);
    const Color lightGrey = Color(0xFFF5F5F7);
    const Color darkText = Color(0xFF22223B);
    const Color errorRed = Color(0xFFCF6679);

    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: lilacPurple, onPrimary: darkText,
      secondary: softTeal, onSecondary: darkText,
      surface: lightGrey, onSurface: darkText,
      background: lightGrey, onBackground: darkText,
      error: errorRed, onError: darkText,
    );
    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: lilacPurple, onPrimary: Colors.white,
      secondary: softTeal, onSecondary: Colors.white,
      surface: const Color(0xFF2A2A40), onSurface: Colors.white,
      background: darkText, onBackground: Colors.white,
      error: errorRed, onError: Colors.black,
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
          theme: ThemeData.from(colorScheme: lightScheme, useMaterial3: true),
          darkTheme: ThemeData.from(colorScheme: darkScheme, useMaterial3: true),
          themeMode: themeController.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AuthGate(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

// AuthGate has been moved to lib/auth/auth_gate.dart
// AuthScreen has been moved to lib/auth/auth_screen.dart
// MainScaffold has been moved to lib/shared/main_scaffold.dart
// ImageGeneratorScreen has been moved to lib/features/image_generator/image_generator_screen.dart
// AccountSection has been moved to lib/features/account/account_section.dart
