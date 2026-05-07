import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_gate.dart';
import 'shared/connectivity_service.dart';
import 'shared/design_system/design_tokens.dart';
import 'shared/notifiers/subscription_status_notifier.dart';
import 'shared/offline_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Theme controller — dark by default, persisted in SharedPreferences.
class ThemeController extends ChangeNotifier {
  bool _isDarkMode = true;
  bool get isDarkMode => _isDarkMode;

  ThemeController() {
    _load();
  }

  Future<void> _load() async {
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top],
  );

  await Firebase.initializeApp();
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
      ],
      child: const VisionSparkApp(),
    ),
  );
}

class VisionSparkApp extends StatelessWidget {
  const VisionSparkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return StreamBuilder<bool>(
      stream: ConnectivityService().onStatusChange,
      initialData: ConnectivityService().isOnline,
      builder: (context, snapshot) {
        final online = snapshot.data ?? true;
        if (!online) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(VSColorSchemes.light),
            darkTheme: _buildTheme(VSColorSchemes.dark),
            themeMode: theme.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: OfflineScreen(onRetry: () => ConnectivityService().retryCheck()),
          );
        }
        return MaterialApp(
          title: 'VisionSpark',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: _buildTheme(VSColorSchemes.light),
          darkTheme: _buildTheme(VSColorSchemes.dark),
          themeMode: theme.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AuthGate(),
        );
      },
    );
  }
}

ThemeData _buildTheme(ColorScheme cs) {
  final base = ThemeData.from(colorScheme: cs, useMaterial3: true);
  final isDark = cs.brightness == Brightness.dark;

  return base.copyWith(
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,

    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: cs.onSurface,
        fontWeight: VSTypography.weightSemiBold,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: cs.onSurface),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? cs.surfaceContainerHigh : cs.surfaceContainer,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: VSDesignTokens.space4,
        vertical: VSDesignTokens.space4,
      ),
      labelStyle: TextStyle(color: cs.onSurfaceVariant),
      hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
      prefixIconColor: cs.primary,
      border: _border(cs.outline.withValues(alpha: 0.3)),
      enabledBorder: _border(cs.outline.withValues(alpha: 0.3)),
      focusedBorder: _border(cs.primary, width: 2),
      errorBorder: _border(cs.error, width: 1.5),
      focusedErrorBorder: _border(cs.error, width: 2),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: VSDesignTokens.space5, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        ),
        textStyle: const TextStyle(fontWeight: VSTypography.weightSemiBold),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: VSDesignTokens.space5, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: VSDesignTokens.space5, vertical: 14),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        padding: const EdgeInsets.symmetric(horizontal: VSDesignTokens.space3, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusS),
        ),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.primary,
      labelStyle: TextStyle(color: cs.onSurface),
      side: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: VSDesignTokens.space3,
        vertical: VSDesignTokens.space1,
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
      ),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: cs.onSurface,
        fontWeight: VSTypography.weightBold,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      ),
      elevation: 4,
    ),

    dividerTheme: DividerThemeData(
      color: cs.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHigh,
      circularTrackColor: cs.surfaceContainerHigh,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.surfaceContainerHigh,
      thumbColor: cs.primary,
      overlayColor: cs.primary.withValues(alpha: 0.18),
      trackHeight: 4,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? cs.onPrimary : cs.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? cs.primary
            : cs.surfaceContainerHigh,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),

    listTileTheme: ListTileThemeData(
      iconColor: cs.onSurfaceVariant,
      titleTextStyle: base.textTheme.titleMedium?.copyWith(
        color: cs.onSurface,
        fontWeight: VSTypography.weightMedium,
      ),
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      ),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: cs.onPrimary,
      unselectedLabelColor: cs.onSurfaceVariant,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
    ),
  );
}

OutlineInputBorder _border(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      borderSide: BorderSide(color: color, width: width),
    );
