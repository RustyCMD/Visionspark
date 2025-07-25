import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/design_system/design_system.dart';

void main() {
  group('VSButton Tests', () {
    testWidgets('VSButton renders correctly with text', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Test Button',
              onPressed: () {},
              variant: VSButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('VSButton handles disabled state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Disabled Button',
              onPressed: null,
              variant: VSButtonVariant.primary,
            ),
          ),
        ),
      );

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('VSButton shows loading state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Loading Button',
              onPressed: () {},
              isLoading: true,
              variant: VSButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading Button'), findsNothing);
    });

    testWidgets('VSButton with icon renders correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Icon Button',
              icon: const Icon(Icons.star),
              onPressed: () {},
              variant: VSButtonVariant.primary,
            ),
          ),
        ),
      );

      expect(find.text('Icon Button'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('VSButton responds to tap', (WidgetTester tester) async {
      bool tapped = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Tap Button',
              onPressed: () => tapped = true,
              variant: VSButtonVariant.primary,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      expect(tapped, isTrue);
    });
  });

  group('VSCard Tests', () {
    testWidgets('VSCard renders with child content', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSCard(
              child: Text('Card Content'),
            ),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('VSCard applies custom padding', (WidgetTester tester) async {
      const customPadding = EdgeInsets.all(20.0);
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSCard(
              padding: customPadding,
              child: Text('Padded Content'),
            ),
          ),
        ),
      );

      final padding = tester.widget<Padding>(find.byType(Padding));
      expect(padding.padding, equals(customPadding));
    });
  });

  group('VSAccessibleTextField Tests', () {
    testWidgets('VSAccessibleTextField renders correctly', (WidgetTester tester) async {
      final controller = TextEditingController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSAccessibleTextField(
              controller: controller,
              labelText: 'Test Field',
              hintText: 'Enter text',
            ),
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Test Field'), findsOneWidget);
    });

    testWidgets('VSAccessibleTextField validates input', (WidgetTester tester) async {
      final controller = TextEditingController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              child: VSAccessibleTextField(
                controller: controller,
                labelText: 'Required Field',
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'This field is required';
                  }
                  return null;
                },
              ),
            ),
          ),
        ),
      );

      // Trigger validation by submitting empty form
      final form = tester.widget<Form>(find.byType(Form));
      final formState = form.key as GlobalKey<FormState>;
      expect(formState.currentState!.validate(), isFalse);
    });
  });

  group('VSLoadingIndicator Tests', () {
    testWidgets('VSLoadingIndicator renders with message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSLoadingIndicator(
              message: 'Loading...',
            ),
          ),
        ),
      );

      expect(find.text('Loading...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('VSLoadingIndicator renders without message', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSLoadingIndicator(),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });
  });

  group('VSEmptyState Tests', () {
    testWidgets('VSEmptyState renders with all elements', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSEmptyState(
              icon: Icons.inbox,
              title: 'No Items',
              subtitle: 'Add some items to get started',
              action: VSButton(
                text: 'Add Item',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.text('No Items'), findsOneWidget);
      expect(find.text('Add some items to get started'), findsOneWidget);
      expect(find.text('Add Item'), findsOneWidget);
    });
  });

  group('VSResponsiveText Tests', () {
    testWidgets('VSResponsiveText renders with base style', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveText(
              text: 'Responsive Text',
              baseStyle: TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),
        ),
      );

      expect(find.text('Responsive Text'), findsOneWidget);
    });
  });

  group('VSResponsiveSpacing Tests', () {
    testWidgets('VSResponsiveSpacing renders SizedBox', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Text('Before'),
                VSResponsiveSpacing(),
                Text('After'),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('Before'), findsOneWidget);
      expect(find.text('After'), findsOneWidget);
    });
  });

  group('VSResponsiveLayout Tests', () {
    testWidgets('VSResponsiveLayout constrains child width', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveLayout(
              child: Container(
                width: double.infinity,
                height: 100,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Container), findsOneWidget);
      expect(find.byType(Center), findsOneWidget);
    });
  });

  group('VSResponsiveBuilder Tests', () {
    testWidgets('VSResponsiveBuilder builds different widgets for different breakpoints', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveBuilder(
              builder: (context, breakpoint) {
                switch (breakpoint) {
                  case VSBreakpoint.mobile:
                    return Text('Mobile');
                  case VSBreakpoint.tablet:
                    return Text('Tablet');
                  case VSBreakpoint.desktop:
                    return Text('Desktop');
                  case VSBreakpoint.large:
                    return Text('Large');
                }
              },
            ),
          ),
        ),
      );

      // Should render mobile layout by default in test environment
      expect(find.text('Mobile'), findsOneWidget);
    });
  });
}
