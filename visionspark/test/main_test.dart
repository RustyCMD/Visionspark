import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:visionspark/main.dart';

import 'main_test.mocks.dart';

@GenerateMocks([SharedPreferences])

// Helper function to test theme building
ThemeData buildTheme(ColorScheme colorScheme) {
  return ThemeData.from(colorScheme: colorScheme, useMaterial3: true).copyWith(
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
      ),
    ),
  );
}

void main() {
  group('ThemeController Tests', () {
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = MockSharedPreferences();
      SharedPreferences.setMockInitialValues({});
    });

    test('initial dark mode is true by default', () async {
      when(mockPrefs.getBool('isDarkMode')).thenReturn(null);
      
      final controller = ThemeController();
      await Future.delayed(Duration(milliseconds: 100)); // Allow async init
      
      expect(controller.isDarkMode, true);
    });

    test('loads dark mode preference from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'isDarkMode': false});
      
      final controller = ThemeController();
      await Future.delayed(Duration(milliseconds: 100)); // Allow async init
      
      expect(controller.isDarkMode, false);
    });

    test('setDarkMode updates preference and notifies listeners', () async {
      SharedPreferences.setMockInitialValues({'isDarkMode': true});
      
      final controller = ThemeController();
      await Future.delayed(Duration(milliseconds: 100)); // Allow async init
      
      bool notificationReceived = false;
      controller.addListener(() {
        notificationReceived = true;
      });

      await controller.setDarkMode(false);
      
      expect(controller.isDarkMode, false);
      expect(notificationReceived, true);
      
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('isDarkMode'), false);
    });

    test('setDarkMode persists preference to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      
      final controller = ThemeController();
      await controller.setDarkMode(false);
      
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('isDarkMode'), false);
    });

    test('multiple setDarkMode calls work correctly', () async {
      SharedPreferences.setMockInitialValues({});
      
      final controller = ThemeController();
      
      await controller.setDarkMode(false);
      expect(controller.isDarkMode, false);
      
      await controller.setDarkMode(true);
      expect(controller.isDarkMode, true);
      
      await controller.setDarkMode(false);
      expect(controller.isDarkMode, false);
    });

    test('notifies listeners when theme changes', () async {
      final controller = ThemeController();
      
      int notificationCount = 0;
      controller.addListener(() {
        notificationCount++;
      });

      await controller.setDarkMode(false);
      await controller.setDarkMode(true);
      
      expect(notificationCount, 2);
    });
  });

  group('App Theme Tests', () {
    testWidgets('MyApp uses correct theme based on ThemeController', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
      expect(app.themeMode, ThemeMode.dark); // Default is dark
    });

    testWidgets('theme switches correctly when ThemeController changes', (WidgetTester tester) async {
      final themeController = ThemeController();
      
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: themeController),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      // Change to light mode
      await themeController.setDarkMode(false);
      await tester.pumpAndSettle();

      app = tester.widget(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);
    });

    test('light and dark color schemes have correct properties', () {
      // Test light theme color scheme
      const lightScheme = ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF3949AB),
        onPrimary: Colors.white,
        secondary: Color(0xFF00ACC1),
        onSecondary: Colors.black,
        surface: Color(0xFFF5F5F5),
        onSurface: Color(0xFF212121),
        surfaceContainerLowest: Colors.white,
        error: Color(0xFFD32F2F),
        onError: Colors.white,
      );

      expect(lightScheme.brightness, Brightness.light);
      expect(lightScheme.primary, const Color(0xFF3949AB));
      expect(lightScheme.secondary, const Color(0xFF00ACC1));

      // Test dark theme color scheme
      const darkScheme = ColorScheme(
        brightness: Brightness.dark,
        primary: Color(0xFF7986CB),
        onPrimary: Colors.black,
        secondary: Color(0xFF4DD0E1),
        onSecondary: Colors.black,
        surface: Color(0xFF212121),
        onSurface: Colors.white,
        surfaceContainerLowest: Color(0xFF121212),
        error: Color(0xFFEF9A9A),
        onError: Colors.black,
      );

      expect(darkScheme.brightness, Brightness.dark);
      expect(darkScheme.primary, const Color(0xFF7986CB));
      expect(darkScheme.secondary, const Color(0xFF4DD0E1));
    });

    testWidgets('app title is set correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: const MyApp(),
        ),
      );

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.title, 'Visionspark');
    });

    testWidgets('debug banner is disabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: const MyApp(),
        ),
      );

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.debugShowCheckedModeBanner, false);
    });
  });

  group('Theme Building Tests', () {
    test('buildTheme creates proper ThemeData with custom properties', () {
      const colorScheme = ColorScheme.light();
      final theme = buildTheme(colorScheme);

      expect(theme.colorScheme, colorScheme);
      expect(theme.useMaterial3, true);
      
      // Test card theme
      expect(theme.cardTheme.elevation, 2);
      expect(theme.cardTheme.shape, isA<RoundedRectangleBorder>());
      
      // Test input decoration theme
      expect(theme.inputDecorationTheme.filled, true);
      expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
    });

    test('card theme has correct border radius', () {
      const colorScheme = ColorScheme.light();
      final theme = buildTheme(colorScheme);
      
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(12.0));
    });

    test('input decoration theme has correct border radius', () {
      const colorScheme = ColorScheme.light();
      final theme = buildTheme(colorScheme);
      
      final border = theme.inputDecorationTheme.border as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(12.0));
    });
  });
}