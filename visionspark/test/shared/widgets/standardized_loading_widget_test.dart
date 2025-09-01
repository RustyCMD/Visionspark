import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/widgets/standardized_loading_widget.dart';
import 'package:visionspark/shared/services/retry_service.dart';
import 'package:visionspark/shared/design_system/design_system.dart';

void main() {
  group('StandardizedLoadingWidget Tests', () {
    testWidgets('should display loading indicator with correct message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              currentAttempt: 1,
              maxAttempts: 3,
            ),
          ),
        ),
      );

      expect(find.byType(VSLoadingIndicator), findsOneWidget);
      expect(find.text('Checking subscription status...'), findsOneWidget);
    });

    testWidgets('should show progress bar when maxAttempts > 1', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              currentAttempt: 2,
              maxAttempts: 5,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Attempt 2 of 5'), findsOneWidget);
    });

    testWidgets('should hide progress bar when maxAttempts = 1', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              currentAttempt: 1,
              maxAttempts: 1,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Attempt 1 of 1'), findsNothing);
    });

    testWidgets('should show retry message for subsequent attempts', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              currentAttempt: 3,
              maxAttempts: 5,
            ),
          ),
        ),
      );

      expect(find.text('Checking subscription status... (retry 3)'), findsOneWidget);
    });

    testWidgets('should show custom message when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              customMessage: 'Custom loading message',
            ),
          ),
        ),
      );

      expect(find.text('Custom loading message'), findsOneWidget);
    });

    testWidgets('should show cancel button when onCancel is provided', (WidgetTester tester) async {
      bool cancelCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              onCancel: () => cancelCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Cancel'), findsOneWidget);
      
      await tester.tap(find.text('Cancel'));
      expect(cancelCalled, true);
    });

    testWidgets('should show elapsed time when enabled', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              elapsed: const Duration(seconds: 45),
              showElapsedTime: true,
            ),
          ),
        ),
      );

      expect(find.text('Elapsed: 45s'), findsOneWidget);
    });

    testWidgets('should format elapsed time correctly for minutes', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedLoadingWidget(
              operationType: RetryOperationType.subscriptionStatus,
              elapsed: const Duration(minutes: 2, seconds: 30),
              showElapsedTime: true,
            ),
          ),
        ),
      );

      expect(find.text('Elapsed: 2m 30s'), findsOneWidget);
    });
  });

  group('StandardizedErrorWidget Tests', () {
    testWidgets('should display error message and retry button for retryable errors', (WidgetTester tester) async {
      const result = RetryResult<String>(
        success: false,
        attempts: 3,
        totalTime: Duration(seconds: 10),
        error: 'Network timeout',
        wasRetryable: true,
      );

      bool retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedErrorWidget(
              result: result,
              operationType: RetryOperationType.subscriptionStatus,
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Subscription Status Failed'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      
      await tester.tap(find.text('Try Again'));
      expect(retryCalled, true);
    });

    testWidgets('should not show retry button for non-retryable errors', (WidgetTester tester) async {
      const result = RetryResult<String>(
        success: false,
        attempts: 1,
        totalTime: Duration(seconds: 1),
        error: 'Invalid input',
        wasRetryable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedErrorWidget(
              result: result,
              operationType: RetryOperationType.subscriptionStatus,
            ),
          ),
        ),
      );

      expect(find.text('Subscription Status Error'), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
    });

    testWidgets('should show attempt count and duration', (WidgetTester tester) async {
      const result = RetryResult<String>(
        success: false,
        attempts: 5,
        totalTime: Duration(minutes: 1, seconds: 30),
        error: 'Network timeout',
        wasRetryable: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedErrorWidget(
              result: result,
              operationType: RetryOperationType.subscriptionStatus,
            ),
          ),
        ),
      );

      expect(find.text('Attempted 5 times over 1m 30s'), findsOneWidget);
    });

    testWidgets('should show custom error message when provided', (WidgetTester tester) async {
      const result = RetryResult<String>(
        success: false,
        attempts: 1,
        totalTime: Duration(seconds: 1),
        error: 'Network timeout',
        wasRetryable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedErrorWidget(
              result: result,
              operationType: RetryOperationType.subscriptionStatus,
              customMessage: 'Custom error message for testing',
            ),
          ),
        ),
      );

      expect(find.text('Custom error message for testing'), findsOneWidget);
    });

    testWidgets('should show cancel button when onCancel is provided', (WidgetTester tester) async {
      const result = RetryResult<String>(
        success: false,
        attempts: 3,
        totalTime: Duration(seconds: 10),
        error: 'Network timeout',
        wasRetryable: true,
      );

      bool cancelCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StandardizedErrorWidget(
              result: result,
              operationType: RetryOperationType.subscriptionStatus,
              onCancel: () => cancelCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Cancel'), findsOneWidget);
      
      await tester.tap(find.text('Cancel'));
      expect(cancelCalled, true);
    });
  });

  group('Message Generation Tests', () {
    testWidgets('should generate correct messages for different operation types', (WidgetTester tester) async {
      final operationTypes = [
        RetryOperationType.subscriptionStatus,
        RetryOperationType.purchaseValidation,
        RetryOperationType.imageGeneration,
        RetryOperationType.imageEnhancement,
        RetryOperationType.profileUpdate,
        RetryOperationType.networkRequest,
      ];

      final expectedMessages = [
        'Checking subscription status...',
        'Validating your purchase...',
        'Generating your image...',
        'Enhancing your image...',
        'Updating your profile...',
        'Processing your request...',
      ];

      for (int i = 0; i < operationTypes.length; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StandardizedLoadingWidget(
                operationType: operationTypes[i],
                currentAttempt: 1,
                maxAttempts: 1,
              ),
            ),
          ),
        );

        expect(find.text(expectedMessages[i]), findsOneWidget);
      }
    });
  });
}
