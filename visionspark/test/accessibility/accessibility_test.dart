import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/accessibility/accessibility_utils.dart' as utils;
import 'package:visionspark/shared/design_system/design_system.dart';

void main() {
  group('VSAccessibility Tests', () {
    test('calculateContrastRatio returns correct values', () {
      // Test black on white (maximum contrast)
      final blackOnWhite = utils.VSAccessibility.calculateContrastRatio(Colors.black, Colors.white);
      expect(blackOnWhite, closeTo(21.0, 0.1));

      // Test white on black (same as black on white)
      final whiteOnBlack = utils.VSAccessibility.calculateContrastRatio(Colors.white, Colors.black);
      expect(whiteOnBlack, closeTo(21.0, 0.1));

      // Test same colors (minimum contrast)
      final sameColor = utils.VSAccessibility.calculateContrastRatio(Colors.red, Colors.red);
      expect(sameColor, closeTo(1.0, 0.1));
    });

    test('meetsContrastRequirements validates correctly', () {
      // High contrast should pass
      expect(
        utils.VSAccessibility.meetsContrastRequirements(Colors.black, Colors.white),
        isTrue,
      );

      // Low contrast should fail
      expect(
        utils.VSAccessibility.meetsContrastRequirements(
          Colors.grey[400]!,
          Colors.grey[300]!,
        ),
        isFalse,
      );

      // Large text has lower requirements
      expect(
        utils.VSAccessibility.meetsContrastRequirements(
          Colors.grey[600]!,
          Colors.white,
          isLargeText: true,
        ),
        isTrue,
      );
    });

    test('meetsTouchTargetSize validates correctly', () {
      // Size that meets minimum
      expect(
        utils.VSAccessibility.meetsTouchTargetSize(Size(48, 48)),
        isTrue,
      );

      // Size that doesn't meet minimum
      expect(
        utils.VSAccessibility.meetsTouchTargetSize(Size(30, 30)),
        isFalse,
      );

      // Size with one dimension too small
      expect(
        utils.VSAccessibility.meetsTouchTargetSize(Size(48, 30)),
        isFalse,
      );
    });

    test('createSemanticLabel builds correct labels', () {
      // Basic label
      expect(
        utils.VSAccessibility.createSemanticLabel(label: 'Test'),
        equals('Test'),
      );

      // Label with value
      expect(
        utils.VSAccessibility.createSemanticLabel(label: 'Volume', value: '50%'),
        equals('Volume, 50%'),
      );

      // Button with selection state
      expect(
        utils.VSAccessibility.createSemanticLabel(
          label: 'Menu',
          isButton: true,
          isSelected: true,
        ),
        equals('Menu, button, selected'),
      );

      // Expandable element
      expect(
        utils.VSAccessibility.createSemanticLabel(
          label: 'Dropdown',
          isExpanded: false,
          hint: 'Double tap to expand',
        ),
        equals('Dropdown, collapsed, Double tap to expand'),
      );
    });
  });

  group('VSAccessibilityTesting Tests', () {
    test('testColorContrast returns comprehensive results', () {
      final result = utils.VSAccessibilityTesting.testColorContrast(Colors.black, Colors.white);

      expect(result['ratio'], closeTo(21.0, 0.1));
      expect(result['passesAA'], isTrue);
      expect(result['passesAAA'], isTrue);
      expect(result['passesAALarge'], isTrue);
      expect(result['passesAAALarge'], isTrue);
    });

    test('testTouchTargetSize returns comprehensive results', () {
      final result = utils.VSAccessibilityTesting.testTouchTargetSize(Size(40, 40));

      expect(result['width'], equals(40.0));
      expect(result['height'], equals(40.0));
      expect(result['meetsMinimum'], isFalse);
      expect(result['minimumRequired'], equals(48.0));
    });
  });

  group('Accessible Widget Tests', () {
    testWidgets('VSAccessibleButton has proper semantics', (WidgetTester tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSAccessibleButton(
              onPressed: () => tapped = true,
              semanticLabel: 'Test accessible button',
              tooltip: 'This is a test button',
              child: Text('Button'),
            ),
          ),
        ),
      );

      // Check that semantics are properly applied
      final semantics = tester.getSemantics(find.byType(VSAccessibleButton));
      expect(semantics.label, contains('Test accessible button'));
      // Check that the semantics data contains tap action
      final semanticsData = semantics.getSemanticsData();
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);

      // Test interaction
      await tester.tap(find.byType(VSAccessibleButton));
      expect(tapped, isTrue);
    });

    testWidgets('VSAccessibleTextField has proper semantics', (WidgetTester tester) async {
      final controller = TextEditingController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSAccessibleTextField(
              controller: controller,
              labelText: 'Email',
              semanticLabel: 'Email address input field',
              hintText: 'Enter your email',
            ),
          ),
        ),
      );

      // Check that the text field is accessible
      expect(find.byType(TextField), findsOneWidget);
      
      // Test text input
      await tester.enterText(find.byType(TextField), 'test@example.com');
      expect(controller.text, equals('test@example.com'));
    });

    testWidgets('VSButton meets minimum touch target size', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Small Button',
              onPressed: () {},
              size: VSButtonSize.small,
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(ElevatedButton);
      final buttonSize = tester.getSize(buttonFinder);
      
      // Even small buttons should meet minimum touch target
      expect(buttonSize.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('VSCard has proper accessibility structure', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSCard(
              child: Column(
                children: [
                  Text('Card Title'),
                  Text('Card Content'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Card Title'), findsOneWidget);
      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('VSLoadingIndicator announces loading state', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSLoadingIndicator(
              message: 'Loading data...',
            ),
          ),
        ),
      );

      expect(find.text('Loading data...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('VSEmptyState provides helpful guidance', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No messages',
              subtitle: 'Your inbox is empty',
              action: VSButton(
                text: 'Compose',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('No messages'), findsOneWidget);
      expect(find.text('Your inbox is empty'), findsOneWidget);
      expect(find.text('Compose'), findsOneWidget);
    });
  });

  group('Responsive Accessibility Tests', () {
    testWidgets('VSResponsiveText scales appropriately', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveText(
              text: 'Responsive Text',
              baseStyle: TextStyle(fontSize: 16),
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Responsive Text'));
      expect(textWidget.style?.fontSize, isNotNull);
    });

    testWidgets('VSResponsiveLayout adapts to screen size', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveLayout(
              child: SizedBox(
                width: double.infinity,
                height: 100,
                child: Text('Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(Container), findsOneWidget);
    });

    testWidgets('VSResponsiveBuilder provides appropriate breakpoint', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveBuilder(
              builder: (context, breakpoint) {
                return Text('Breakpoint: ${breakpoint.name}');
              },
            ),
          ),
        ),
      );

      // In test environment, should default to mobile
      expect(find.textContaining('mobile'), findsOneWidget);
    });
  });

  group('Focus Management Tests', () {
    testWidgets('Focus can be managed programmatically', (WidgetTester tester) async {
      final focusNode = FocusNode();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focusNode),
                ElevatedButton(
                  onPressed: () => focusNode.requestFocus(),
                  child: Text('Focus Field'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(focusNode.hasFocus, isFalse);
      
      await tester.tap(find.text('Focus Field'));
      await tester.pump();
      
      expect(focusNode.hasFocus, isTrue);
      
      focusNode.dispose();
    });
  });
}
