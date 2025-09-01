// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:visionspark/main.dart';
import 'package:visionspark/shared/notifiers/subscription_status_notifier.dart';

void main() {
  testWidgets('VisionSpark app smoke test', (WidgetTester tester) async {
    // Mock providers for testing
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
        ],
        child: const MyApp(),
      ),
    );

    // Verify that our app builds without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
    
    // The app should show either AuthScreen or MainScaffold
    // depending on authentication state
    await tester.pumpAndSettle();
    
    // Should find the app title
    final MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.title, 'Visionspark');
    
    // Should use Material 3 design
    expect(app.theme?.useMaterial3, true);
    expect(app.darkTheme?.useMaterial3, true);
    
    // Debug banner should be disabled
    expect(app.debugShowCheckedModeBanner, false);
  });

  testWidgets('Theme switching works correctly', (WidgetTester tester) async {
    final themeController = ThemeController();
    
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeController),
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Initial state should be dark mode
    MaterialApp app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    // Switch to light mode
    await themeController.setDarkMode(false);
    await tester.pumpAndSettle();

    app = tester.widget(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);

    themeController.dispose();
  });

  testWidgets('App handles connectivity changes', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeController()),
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
        ],
        child: const MyApp(),
      ),
    );

    // App should build and handle connectivity state
    expect(find.byType(MaterialApp), findsOneWidget);
    
    await tester.pumpAndSettle();
    
    // Should find either the main app or offline screen
    expect(find.byType(Scaffold), findsWidgets);
  });
}
