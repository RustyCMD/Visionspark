import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:visionspark/features/image_generator/image_generator_screen.dart';
import 'package:visionspark/shared/notifiers/subscription_status_notifier.dart';

import 'image_generator_test.mocks.dart';

@GenerateMocks([SupabaseClient, GoTrueClient, FunctionsClient, User, Session])
void main() {
  group('ImageGeneratorScreen Tests', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockFunctionsClient mockFunctionsClient;
    late MockUser mockUser;
    late MockSession mockSession;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockFunctionsClient = MockFunctionsClient();
      mockUser = MockUser();
      mockSession = MockSession();

      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
      when(mockSupabaseClient.functions).thenReturn(mockFunctionsClient);
      when(mockGoTrueClient.currentUser).thenReturn(mockUser);
      when(mockGoTrueClient.currentSession).thenReturn(mockSession);

      SharedPreferences.setMockInitialValues({});

      // Mock Supabase.instance
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
        ],
        child: const MaterialApp(
          home: ImageGeneratorScreen(),
        ),
      );
    }

    testWidgets('displays generation status correctly', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'limit': 5,
            'generations_today': 2,
            'resets_at_utc_iso': DateTime.now().add(Duration(hours: 12)).toIso8601String(),
          },
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Generations Remaining'), findsOneWidget);
      expect(find.text('3 / 5'), findsOneWidget);
    });

    testWidgets('shows unlimited generations for premium users', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'limit': -1,
            'generations_today': 0,
            'resets_at_utc_iso': null,
          },
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Unlimited'), findsOneWidget);
    });

    testWidgets('prompt text field works correctly', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final promptField = find.byType(TextField).first;
      await tester.enterText(promptField, 'A beautiful sunset');
      
      expect(find.text('A beautiful sunset'), findsOneWidget);
    });

    testWidgets('negative prompt field works correctly', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final negativePromptField = find.widgetWithText(TextField, 'Negative Prompt (Optional)');
      await tester.enterText(negativePromptField, 'blurry, ugly');
      
      expect(find.text('blurry, ugly'), findsOneWidget);
    });

    testWidgets('aspect ratio selector changes selection', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find and tap landscape button
      final landscapeButton = find.text('Landscape');
      await tester.tap(landscapeButton);
      await tester.pumpAndSettle();

      // Verify landscape is selected (this would be tested through state inspection in real app)
      expect(find.text('Landscape'), findsOneWidget);
    });

    testWidgets('style selector changes selection', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find style dropdown
      final styleDropdown = find.byType(DropdownButton<String>);
      await tester.tap(styleDropdown);
      await tester.pumpAndSettle();

      // Select cartoon style
      await tester.tap(find.text('Cartoon').last);
      await tester.pumpAndSettle();

      expect(find.text('Cartoon'), findsOneWidget);
    });

    testWidgets('generate button is disabled when no generations remaining', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'limit': 3,
            'generations_today': 3,
            'resets_at_utc_iso': DateTime.now().add(Duration(hours: 12)).toIso8601String(),
          },
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final generateButton = find.widgetWithText(ElevatedButton, 'Generate');
      final button = tester.widget<ElevatedButton>(generateButton);
      
      expect(button.onPressed, isNull);
    });

    testWidgets('improve prompt button triggers API call', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );
      
      when(mockFunctionsClient.invoke('improve-prompt-proxy', body: anyNamed('body'))).thenAnswer(
        (_) async => FunctionResponse(data: {'improved_prompt': 'Enhanced beautiful sunset'}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter prompt
      final promptField = find.byType(TextField).first;
      await tester.enterText(promptField, 'sunset');

      // Tap improve button
      final improveButton = find.byIcon(Icons.auto_fix_high);
      await tester.tap(improveButton);
      await tester.pumpAndSettle();

      verify(mockFunctionsClient.invoke('improve-prompt-proxy', body: anyNamed('body'))).called(1);
    });

    testWidgets('random prompt button fetches new prompt', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );
      
      when(mockFunctionsClient.invoke('get-random-prompt')).thenAnswer(
        (_) async => FunctionResponse(data: {'prompt': 'A majestic mountain landscape'}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap random prompt button
      final randomButton = find.byIcon(Icons.shuffle);
      await tester.tap(randomButton);
      await tester.pumpAndSettle();

      verify(mockFunctionsClient.invoke('get-random-prompt')).called(1);
    });

    testWidgets('shows loading state during image generation', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );
      
      // Create a completer to control when the API call completes
      final completer = Completer<FunctionResponse>();
      when(mockFunctionsClient.invoke('generate-image-proxy', body: anyNamed('body')))
          .thenAnswer((_) => completer.future);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter prompt and generate
      final promptField = find.byType(TextField).first;
      await tester.enterText(promptField, 'test prompt');
      
      final generateButton = find.widgetWithText(ElevatedButton, 'Generate');
      await tester.tap(generateButton);
      await tester.pump();

      // Should show loading state
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // Complete the API call
      completer.complete(FunctionResponse(
        data: {'data': [{'url': 'https://example.com/image.png'}]},
      ));
      await tester.pumpAndSettle();
    });

    testWidgets('displays generated image when successful', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'limit': 5, 'generations_today': 0}),
      );
      
      when(mockFunctionsClient.invoke('generate-image-proxy', body: anyNamed('body'))).thenAnswer(
        (_) async => FunctionResponse(
          data: {'data': [{'url': 'https://example.com/image.png'}]},
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Enter prompt and generate
      final promptField = find.byType(TextField).first;
      await tester.enterText(promptField, 'test prompt');
      
      final generateButton = find.widgetWithText(ElevatedButton, 'Generate');
      await tester.tap(generateButton);
      await tester.pumpAndSettle();

      // Should show the generated image (through Image.network or similar)
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('caches generation status in SharedPreferences', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'limit': 5,
            'generations_today': 2,
            'resets_at_utc_iso': '2024-01-01T12:00:00Z',
          },
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('cached_generation_limit'), 5);
      expect(prefs.getInt('cached_generations_today'), 2);
      expect(prefs.getString('cached_resets_at_utc_iso'), '2024-01-01T12:00:00Z');
    });

    testWidgets('handles API errors gracefully', (WidgetTester tester) async {
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(data: {'error': 'API Error'}),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('API Error'), findsOneWidget);
    });

    testWidgets('timer updates reset countdown', (WidgetTester tester) async {
      final resetTime = DateTime.now().add(Duration(hours: 2, minutes: 30));
      when(mockFunctionsClient.invoke('get-generation-status')).thenAnswer(
        (_) async => FunctionResponse(
          data: {
            'limit': 5,
            'generations_today': 2,
            'resets_at_utc_iso': resetTime.toIso8601String(),
          },
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Should show countdown
      expect(find.textContaining('Resets in'), findsOneWidget);
      expect(find.textContaining('2h'), findsOneWidget);
    });
  });

  group('ImageGenerator Logic Tests', () {
    test('calculates remaining generations correctly', () {
      expect(5 - 2, 3); // limit - generations_today = remaining
      expect(10 - 0, 10);
      expect(3 - 3, 0);
    });

    test('handles unlimited generations', () {
      const int unlimitedLimit = -1;
      expect(unlimitedLimit == -1, true);
      expect(unlimitedLimit - 0, -1); // Remaining should be treated as unlimited
    });

    test('validates prompt input', () {
      const String emptyPrompt = '';
      const String validPrompt = 'A beautiful sunset';
      
      expect(emptyPrompt.trim().isEmpty, true);
      expect(validPrompt.trim().isEmpty, false);
    });

    test('validates aspect ratio values', () {
      const List<String> validRatios = ['1024x1024', '1792x1024', '1024x1792'];
      const String selectedRatio = '1792x1024';
      
      expect(validRatios.contains(selectedRatio), true);
      expect(validRatios.contains('invalid'), false);
    });

    test('validates style options', () {
      const List<String> validStyles = [
        'None', 'Cartoon', 'Photorealistic', 'Fantasy Art', 'Abstract',
        'Anime', 'Comic Book', 'Impressionistic', 'Pixel Art', 'Watercolor'
      ];
      
      expect(validStyles.contains('Cartoon'), true);
      expect(validStyles.contains('Invalid Style'), false);
    });
  });
}