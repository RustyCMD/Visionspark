import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visionspark/main.dart';
import 'package:visionspark/shared/notifiers/subscription_status_notifier.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('VisionSpark app smoke test', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
        ],
        child: const VisionSparkApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'VisionSpark');
    expect(app.theme?.useMaterial3, true);
    expect(app.darkTheme?.useMaterial3, true);
    expect(app.debugShowCheckedModeBanner, false);
  });

  testWidgets('Theme switches when controller toggles', (tester) async {
    final controller = ThemeController();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
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
}
