import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionspark/main.dart';

void main() {
  group('ThemeController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to dark mode when no preference is stored', () async {
      final c = ThemeController();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(c.isDarkMode, true);
    });

    test('reads stored preference', () async {
      SharedPreferences.setMockInitialValues({'isDarkMode': false});
      final c = ThemeController();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(c.isDarkMode, false);
    });

    test('setDarkMode persists and notifies', () async {
      final c = ThemeController();
      var notified = 0;
      c.addListener(() => notified++);

      await c.setDarkMode(false);
      expect(c.isDarkMode, false);
      expect(notified, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('isDarkMode'), false);

      await c.setDarkMode(true);
      expect(c.isDarkMode, true);
      expect(notified, 2);
    });
  });

  group('VisionSparkApp', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('builds with light + dark theme and dark by default',
        (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ThemeController()),
          ],
          child: const VisionSparkApp(),
        ),
      );
      await tester.pumpAndSettle();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
      expect(app.themeMode, ThemeMode.dark);
      expect(app.title, 'VisionSpark');
      expect(app.debugShowCheckedModeBanner, false);
    });

    testWidgets('switches theme when controller toggles', (tester) async {
      final controller = ThemeController();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: controller),
          ],
          child: const VisionSparkApp(),
        ),
      );
      await tester.pumpAndSettle();

      var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);

      await controller.setDarkMode(false);
      await tester.pumpAndSettle();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.light);
    });
  });
}
