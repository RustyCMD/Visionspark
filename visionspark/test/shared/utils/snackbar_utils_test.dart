import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/utils/snackbar_utils.dart';

void main() {
  group('SnackbarUtils Tests', () {
    late Widget testApp;
    late GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;

    setUp(() {
      scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
      testApp = MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(
          body: SizedBox(),
        ),
      );
    });

    testWidgets('showErrorSnackbar displays error message with correct styling', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      showErrorSnackbar(context, 'Test error message');
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Test error message'), findsOneWidget);

      // Check styling
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Theme.of(context).colorScheme.error);
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.margin, const EdgeInsets.all(10));
    });

    testWidgets('showSuccessSnackbar displays success message with correct styling', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      showSuccessSnackbar(context, 'Test success message');
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Test success message'), findsOneWidget);

      // Check styling
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.backgroundColor, Colors.green);
      expect(snackBar.behavior, SnackBarBehavior.floating);
      expect(snackBar.margin, const EdgeInsets.all(10));
    });

    testWidgets('showErrorSnackbar handles unmounted context gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      // Remove the widget to simulate unmounted context
      await tester.pumpWidget(const SizedBox());
      
      // This should not throw an exception
      expect(() => showErrorSnackbar(context, 'Test message'), returnsNormally);
    });

    testWidgets('showSuccessSnackbar handles unmounted context gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      // Remove the widget to simulate unmounted context
      await tester.pumpWidget(const SizedBox());
      
      // This should not throw an exception
      expect(() => showSuccessSnackbar(context, 'Test message'), returnsNormally);
    });

    testWidgets('multiple snackbar calls remove previous snackbar', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      showErrorSnackbar(context, 'First message');
      await tester.pump();
      
      showSuccessSnackbar(context, 'Second message');
      await tester.pump();

      // Should only show the latest snackbar
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
      expect(find.text('First message'), findsNothing);
    });

    testWidgets('snackbar has rounded corners', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      showErrorSnackbar(context, 'Test message');
      await tester.pump();

      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.shape, isA<RoundedRectangleBorder>());
      
      final shape = snackBar.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(10));
    });

    testWidgets('empty message strings are handled', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      showErrorSnackbar(context, '');
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(''), findsOneWidget);
    });

    testWidgets('long messages are displayed properly', (WidgetTester tester) async {
      await tester.pumpWidget(testApp);
      
      final BuildContext context = tester.element(find.byType(Scaffold));
      
      const longMessage = 'This is a very long error message that should still be displayed properly in the snackbar without causing any issues';
      
      showErrorSnackbar(context, longMessage);
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(longMessage), findsOneWidget);
    });
  });
}