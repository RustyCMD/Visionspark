import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:visionspark/auth/auth_gate.dart';
import 'package:visionspark/shared/notifiers/subscription_status_notifier.dart';

import 'auth_gate_test.mocks.dart';

@GenerateMocks([SupabaseClient, GoTrueClient, AuthState, Session, User])
void main() {
  group('AuthGate Tests', () {
    late MockSupabaseClient mockSupabaseClient;
    late MockGoTrueClient mockGoTrueClient;
    late MockAuthState mockAuthState;
    late MockSession mockSession;
    late MockUser mockUser;

    setUp(() {
      mockSupabaseClient = MockSupabaseClient();
      mockGoTrueClient = MockGoTrueClient();
      mockAuthState = MockAuthState();
      mockSession = MockSession();
      mockUser = MockUser();

      when(mockSupabaseClient.auth).thenReturn(mockGoTrueClient);
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SubscriptionStatusNotifier()),
        ],
        child: const MaterialApp(
          home: AuthGate(),
        ),
      );
    }

    testWidgets('shows loading indicator when no auth data available', (WidgetTester tester) async {
      when(mockGoTrueClient.onAuthStateChange).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows AuthScreen when no session exists', (WidgetTester tester) async {
      when(mockAuthState.session).thenReturn(null);
      when(mockGoTrueClient.onAuthStateChange).thenAnswer((_) => Stream.value(mockAuthState));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Welcome to VisionSpark'), findsOneWidget);
    });

    testWidgets('shows MainScaffold when session exists', (WidgetTester tester) async {
      when(mockAuthState.session).thenReturn(mockSession);
      when(mockGoTrueClient.onAuthStateChange).thenAnswer((_) => Stream.value(mockAuthState));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('logs auth events to debug console', (WidgetTester tester) async {
      when(mockAuthState.event).thenReturn(AuthChangeEvent.signedIn);
      when(mockAuthState.session).thenReturn(mockSession);
      when(mockGoTrueClient.onAuthStateChange).thenAnswer((_) => Stream.value(mockAuthState));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify the debug print would be called (this is handled by the widget internally)
      verify(mockAuthState.event).called(greaterThan(0));
      verify(mockAuthState.session).called(greaterThan(0));
    });

    testWidgets('handles auth state changes dynamically', (WidgetTester tester) async {
      final controller = StreamController<AuthState>();
      when(mockGoTrueClient.onAuthStateChange).thenAnswer((_) => controller.stream);

      await tester.pumpWidget(createTestWidget());
      
      // Start with no session
      when(mockAuthState.session).thenReturn(null);
      controller.add(mockAuthState);
      await tester.pumpAndSettle();
      
      expect(find.text('Welcome to VisionSpark'), findsOneWidget);

      // Add session
      when(mockAuthState.session).thenReturn(mockSession);
      controller.add(mockAuthState);
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);

      controller.close();
    });
  });
}