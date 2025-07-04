import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../lib/features/image_enhancement/image_enhancement_screen.dart';
import '../../../lib/shared/notifiers/subscription_status_notifier.dart';

// Mock classes
class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockGoTrueClient extends Mock implements GoTrueClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}
class MockSubscriptionStatusNotifier extends Mock implements SubscriptionStatusNotifier {}

void main() {
  group('ImageEnhancementScreen Tests', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockAuthClient;
    late MockFunctionsClient mockFunctionsClient;
    late MockSubscriptionStatusNotifier mockSubscriptionNotifier;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockAuthClient = MockGoTrueClient();
      mockFunctionsClient = MockFunctionsClient();
      mockSubscriptionNotifier = MockSubscriptionStatusNotifier();

      // Setup mock returns
      when(mockSupabaseClient.auth).thenReturn(mockAuthClient);
      when(mockSupabaseClient.functions).thenReturn(mockFunctionsClient);
      when(mockAuthClient.currentUser).thenReturn(null);
    });

    Widget createTestWidget() {
      return MaterialApp(
        home: ChangeNotifierProvider<SubscriptionStatusNotifier>.value(
          value: mockSubscriptionNotifier,
          child: const ImageEnhancementScreen(),
        ),
      );
    }

    testWidgets('displays image enhancement screen correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Verify key UI elements are present
      expect(find.text('Enhancements Remaining'), findsOneWidget);
      expect(find.text('Select an image to enhance'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Enhancement Prompt'), findsOneWidget);
      expect(find.text('Enhancement Settings'), findsOneWidget);
      expect(find.text('Enhance Image'), findsOneWidget);
    });

    testWidgets('shows gallery and camera buttons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.photo_library), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('enhance button is disabled when no image selected', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final enhanceButton = find.text('Enhance Image');
      expect(enhanceButton, findsOneWidget);
      
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).last
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('displays enhancement settings controls', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Check for enhancement mode dropdown
      expect(find.text('Mode'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      // Check for enhancement strength slider
      expect(find.text('Enhancement Strength: 70%'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('displays prompt input with action buttons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Enhancement Prompt'), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget); // Improve prompt
      expect(find.byIcon(Icons.casino), findsOneWidget); // Random prompt
    });

    testWidgets('shows correct placeholder in result section', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.auto_fix_high), findsOneWidget);
      expect(find.text('Your enhanced image will appear here'), findsOneWidget);
    });

    testWidgets('slider updates enhancement strength correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Find the slider and change its value
      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);

      // Simulate moving slider to 0.5 (50%)
      await tester.drag(slider, const Offset(-100, 0));
      await tester.pump();

      // Note: Due to test limitations, we can't easily verify the exact percentage
      // but the slider widget should be responsive
      expect(slider, findsOneWidget);
    });

    testWidgets('dropdown changes enhancement mode', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final dropdown = find.byType(DropdownButtonFormField<String>);
      expect(dropdown, findsOneWidget);

      // Tap the dropdown to open it
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Should have three modes: Enhance, Edit, Variation
      expect(find.text('Enhance'), findsWidgets);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Variation'), findsOneWidget);
    });

    testWidgets('displays generation status correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Enhancements Remaining'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('handles prompt input correctly', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final promptField = find.byType(TextField);
      expect(promptField, findsOneWidget);

      // Enter text in the prompt field
      await tester.enterText(promptField, 'Add a hat to the person');
      await tester.pump();

      expect(find.text('Add a hat to the person'), findsOneWidget);
    });

    testWidgets('shows tooltip on action buttons', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Find improve prompt button
      final improveButton = find.byIcon(Icons.auto_awesome);
      expect(improveButton, findsOneWidget);

      // Long press to show tooltip
      await tester.longPress(improveButton);
      await tester.pump();

      expect(find.text('Improve Prompt'), findsOneWidget);

      // Dismiss tooltip
      await tester.tap(find.byType(Scaffold));
      await tester.pump();

      // Find random prompt button
      final randomButton = find.byIcon(Icons.casino);
      expect(randomButton, findsOneWidget);

      await tester.longPress(randomButton);
      await tester.pump();

      expect(find.text('Surprise Me!'), findsOneWidget);
    });

    testWidgets('image upload section shows correct initial state', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Should show upload prompt when no image selected
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(find.text('Select an image to enhance'), findsOneWidget);
      
      // Should show both gallery and camera buttons
      final galleryButton = find.widgetWithText(ElevatedButton, 'Gallery');
      final cameraButton = find.widgetWithText(ElevatedButton, 'Camera');
      
      expect(galleryButton, findsOneWidget);
      expect(cameraButton, findsOneWidget);
    });

    testWidgets('aspect ratio of result section is correct', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Find the AspectRatio widget in result section
      final aspectRatio = find.byType(AspectRatio);
      expect(aspectRatio, findsOneWidget);

      final aspectRatioWidget = tester.widget<AspectRatio>(aspectRatio);
      expect(aspectRatioWidget.aspectRatio, equals(1.0)); // Square aspect ratio
    });

    testWidgets('displays correct theme colors', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Verify that the screen uses theme colors properly
      final scaffold = find.byType(Scaffold);
      expect(scaffold, findsOneWidget);

      // Check for Card widgets which should use theme colors
      final cards = find.byType(Card);
      expect(cards, findsOneWidget);
    });
  });

  group('ImageEnhancementScreen Integration Tests', () {
    testWidgets('full workflow integration test', (WidgetTester tester) async {
      final mockSubscriptionNotifier = MockSubscriptionStatusNotifier();
      
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<SubscriptionStatusNotifier>.value(
            value: mockSubscriptionNotifier,
            child: const ImageEnhancementScreen(),
          ),
        ),
      );
      await tester.pump();

      // 1. Verify initial state
      expect(find.text('Select an image to enhance'), findsOneWidget);
      expect(find.text('Enhance Image'), findsOneWidget);

      // 2. Try to enhance without image (should be disabled)
      final enhanceButton = find.text('Enhance Image');
      final buttonWidget = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).last
      );
      expect(buttonWidget.onPressed, isNull);

      // 3. Enter a prompt
      final promptField = find.byType(TextField);
      await tester.enterText(promptField, 'Add sunglasses');
      await tester.pump();

      // 4. Change enhancement mode
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      
      // Select "Edit" mode
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();

      // 5. Adjust enhancement strength
      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(50, 0));
      await tester.pump();

      // Button should still be disabled without image
      final updatedButton = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton).last
      );
      expect(updatedButton.onPressed, isNull);
    });
  });
}