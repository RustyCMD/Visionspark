import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/design_system/design_system.dart';
import 'package:visionspark/features/responsive_test/responsive_test_screen.dart';
import 'package:visionspark/features/accessibility_test/accessibility_test_screen.dart';

void main() {
  group('Screen Integration Tests', () {
    testWidgets('ResponsiveTestScreen renders without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveTestScreen(),
        ),
      );

      // Check that main elements are present
      expect(find.text('Responsive Design Test'), findsOneWidget);
      expect(find.text('Current Breakpoint Info'), findsOneWidget);
      expect(find.text('Responsive Grid'), findsOneWidget);
      expect(find.text('Responsive Typography'), findsOneWidget);
      expect(find.text('Responsive Buttons'), findsOneWidget);
      expect(find.text('Responsive Cards'), findsOneWidget);
    });

    testWidgets('ResponsiveTestScreen shows correct breakpoint info', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveTestScreen(),
        ),
      );

      // Should show mobile breakpoint in test environment
      expect(find.textContaining('MOBILE'), findsOneWidget);
      expect(find.textContaining('true'), findsWidgets); // Is Mobile should be true
    });

    testWidgets('ResponsiveTestScreen grid adapts to screen size', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveTestScreen(),
        ),
      );

      // Check that grid items are present
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
    });

    testWidgets('ResponsiveTestScreen buttons work correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResponsiveTestScreen(),
        ),
      );

      // Find and tap primary button
      final primaryButton = find.text('Primary Button');
      expect(primaryButton, findsOneWidget);
      
      await tester.tap(primaryButton);
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('Responsive Dialog'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Dialog should be gone
      expect(find.text('Responsive Dialog'), findsNothing);
    });

    testWidgets('AccessibilityTestScreen renders without errors', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityTestScreen(),
        ),
      );

      // Check that main elements are present
      expect(find.text('Accessibility Test'), findsOneWidget);
      expect(find.text('Device Accessibility Settings'), findsOneWidget);
      expect(find.text('Interactive Elements'), findsOneWidget);
      expect(find.text('Color Contrast Tests'), findsOneWidget);
      expect(find.text('Focus Management'), findsOneWidget);
      expect(find.text('Semantic Elements'), findsOneWidget);
    });

    testWidgets('AccessibilityTestScreen shows device settings', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityTestScreen(),
        ),
      );

      // Check accessibility info is displayed
      expect(find.text('Screen Reader'), findsOneWidget);
      expect(find.text('High Contrast'), findsOneWidget);
      expect(find.text('Reduced Motion'), findsOneWidget);
      expect(find.text('Text Scale Factor'), findsOneWidget);
      expect(find.text('Large Text'), findsOneWidget);
    });

    testWidgets('AccessibilityTestScreen interactive elements work', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityTestScreen(),
        ),
      );

      // Test button interactions
      expect(find.text('Primary Button'), findsOneWidget);
      expect(find.text('Secondary Button'), findsOneWidget);
      expect(find.text('Disabled Button'), findsOneWidget);

      await tester.tap(find.text('Primary Button'));
      await tester.pump();

      // Test switch
      final switchTile = find.byType(SwitchListTile);
      expect(switchTile, findsOneWidget);
      
      await tester.tap(switchTile);
      await tester.pump();

      // Test slider
      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
    });

    testWidgets('AccessibilityTestScreen focus management works', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityTestScreen(),
        ),
      );

      // Find focus management elements
      expect(find.text('Focus Management'), findsOneWidget);
      expect(find.text('Focus Field'), findsOneWidget);
      expect(find.text('Clear Focus'), findsOneWidget);
      expect(find.text('Next Focus'), findsOneWidget);

      // Test focus field button
      await tester.tap(find.text('Focus Field'));
      await tester.pump();

      // Test clear focus button
      await tester.tap(find.text('Clear Focus'));
      await tester.pump();
    });

    testWidgets('AccessibilityTestScreen color contrast tests display', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityTestScreen(),
        ),
      );

      // Check color contrast test elements
      expect(find.text('Color Contrast Tests'), findsOneWidget);
      expect(find.text('Primary Text'), findsOneWidget);
      expect(find.text('Secondary Text'), findsOneWidget);
      expect(find.text('Primary Button'), findsAtLeastNWidgets(1));
      expect(find.text('Error Text'), findsOneWidget);

      // Check contrast ratio information is displayed
      expect(find.textContaining('Contrast Ratio:'), findsAtLeastNWidgets(1));
      expect(find.textContaining('WCAG AA:'), findsAtLeastNWidgets(1));
    });

    testWidgets('AccessibilityTestScreen semantic elements work', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AccessibilityTestScreen(),
        ),
      );

      // Check semantic elements
      expect(find.text('Semantic Elements'), findsOneWidget);
      expect(find.text('Accessible List'), findsOneWidget);
      expect(find.text('Progress Indicator'), findsOneWidget);

      // Check list items
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);

      // Test list item interaction
      await tester.tap(find.text('Item 1'));
      await tester.pump();

      // Check progress indicator
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  group('Design System Component Integration Tests', () {
    testWidgets('VSButton variants render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VSButton(
                  text: 'Primary',
                  onPressed: () {},
                  variant: VSButtonVariant.primary,
                ),
                VSButton(
                  text: 'Secondary',
                  onPressed: () {},
                  variant: VSButtonVariant.secondary,
                ),
                VSButton(
                  text: 'Outline',
                  onPressed: () {},
                  variant: VSButtonVariant.outline,
                ),
                VSButton(
                  text: 'Text',
                  onPressed: () {},
                  variant: VSButtonVariant.text,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Secondary'), findsOneWidget);
      expect(find.text('Outline'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
    });

    testWidgets('VSButton sizes render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VSButton(
                  text: 'Small',
                  onPressed: () {},
                  size: VSButtonSize.small,
                ),
                VSButton(
                  text: 'Medium',
                  onPressed: () {},
                  size: VSButtonSize.medium,
                ),
                VSButton(
                  text: 'Large',
                  onPressed: () {},
                  size: VSButtonSize.large,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
    });

    testWidgets('VSCard with different configurations', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VSCard(
                  child: Text('Basic Card'),
                ),
                VSCard(
                  elevation: 8.0,
                  child: Text('Elevated Card'),
                ),
                VSCard(
                  color: Colors.blue[50],
                  child: Text('Colored Card'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Basic Card'), findsOneWidget);
      expect(find.text('Elevated Card'), findsOneWidget);
      expect(find.text('Colored Card'), findsOneWidget);
    });

    testWidgets('VSResponsiveLayout with different content', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveLayout(
              child: Column(
                children: [
                  VSResponsiveText(
                    text: 'Responsive Title',
                    baseStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  VSResponsiveSpacing(),
                  VSCard(
                    child: Text('Card in responsive layout'),
                  ),
                  VSResponsiveSpacing(),
                  VSButton(
                    text: 'Responsive Button',
                    onPressed: () {},
                    isFullWidth: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Responsive Title'), findsOneWidget);
      expect(find.text('Card in responsive layout'), findsOneWidget);
      expect(find.text('Responsive Button'), findsOneWidget);
    });
  });

  group('Error Handling Tests', () {
    testWidgets('Components handle null values gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                VSButton(
                  text: 'Disabled Button',
                  onPressed: null, // Should handle null gracefully
                ),
                VSCard(
                  child: Text('Card with null properties'),
                  // Other properties can be null
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Disabled Button'), findsOneWidget);
      expect(find.text('Card with null properties'), findsOneWidget);
    });

    testWidgets('Empty states render correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSEmptyState(
              icon: Icons.error_outline,
              title: 'Something went wrong',
              subtitle: 'Please try again later',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Please try again later'), findsOneWidget);
    });
  });
}
