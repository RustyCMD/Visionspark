import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:convert';
import 'shared/offline_screen.dart';
import 'shared/connectivity_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import the new widget locations
import 'auth/auth_gate.dart'; // Corrected path
// No longer need to import http, permission_handler, device_info_plus, Platform, MethodChannel, or dart:convert directly in main.dart
// if they are only used within the widgets that have been moved out.
// However, if MyApp or other remaining parts of main.dart need them, keep them.
// For now, assuming they are encapsulated in their respective moved files.

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Custom theme controller
class ThemeController extends ChangeNotifier {
  bool _isDarkMode = true; // Default to dark mode
  bool get isDarkMode => _isDarkMode;

  ThemeController() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('isDarkMode')) {
      _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    } else {
      _isDarkMode = true; // Default to dark mode if not set
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
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
  final themeController = ThemeController();
  runApp(
    ChangeNotifierProvider(
      create: (_) => themeController,
      child: const MyApp(),
    ),
  );
  _initDeepLinks();
}

StreamSubscription? _sub;
AppLinks? _appLinks;

void _initDeepLinks() {
  _appLinks = AppLinks();
  _sub = _appLinks!.uriLinkStream.listen((Uri? uri) async {
    if (uri != null && uri.scheme == 'visionspark' && uri.host == 'reset-password') {
      // Parse tokens from fragment or query
      final params = Uri.splitQueryString(uri.fragment.isNotEmpty ? uri.fragment : uri.query);
      final accessToken = params['access_token'];
      final refreshToken = params['refresh_token'];
      if (accessToken != null && refreshToken != null) {
        await Supabase.instance.client.auth.recoverSession(jsonEncode({
          'access_token': accessToken,
          'refresh_token': refreshToken,
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': null,
        }));
      }
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (context) => const PasswordResetScreen()),
      );
    }
  }, onError: (err) {});
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeController = Provider.of<ThemeController>(context);
    // New color palette
    const Color lilacPurple = Color(0xFFD0B8E1); // Main
    const Color softTeal = Color(0xFF87CEEB); // Complementary 1
    const Color mutedPeach = Color(0xFFFFDAB9); // Complementary 2
    const Color lightGrey = Color(0xFFF5F5F7); // Neutral background
    const Color darkText = Color(0xFF22223B); // For text on light backgrounds
    const Color errorRed = Color(0xFFCF6679); // Error

    final lightScheme = ColorScheme(
      brightness: Brightness.light,
      primary: lilacPurple,
      onPrimary: darkText,
      secondary: softTeal,
      onSecondary: darkText,
      surface: lightGrey,
      onSurface: darkText,
      background: lightGrey,
      onBackground: darkText,
      error: errorRed,
      onError: darkText,
    );
    final darkScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: lilacPurple,
      onPrimary: Colors.white,
      secondary: softTeal,
      onSecondary: Colors.white,
      surface: Color(0xFF2A2A40),
      onSurface: Colors.white,
      background: darkText,
      onBackground: Colors.white,
      error: errorRed,
      onError: Colors.black,
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

// Add PasswordResetScreen widget
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _success;

  Future<void> _resetPassword() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text.trim()),
      );
      setState(() {
        _success = 'Password updated! You can now log in.';
      });
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to reset password: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter your new password:', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New Password'),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_success != null)
              Text(_success!, style: const TextStyle(color: Colors.green)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _resetPassword,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Reset Password'),
            ),
          ],
        ),
      ),
    );
  }
}
