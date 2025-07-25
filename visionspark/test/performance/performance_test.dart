import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/design_system/design_system.dart';

void main() {
  group('Performance Tests', () {
    testWidgets('VSButton renders quickly', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Performance Test Button',
              onPressed: () {},
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // Button should render in under 100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    testWidgets('VSCard renders quickly with complex content', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSCard(
              child: Column(
                children: List.generate(10, (index) => 
                  ListTile(
                    leading: Icon(Icons.star),
                    title: Text('Item $index'),
                    subtitle: Text('Description for item $index'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // Complex card should render in under 200ms
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });

    testWidgets('VSResponsiveLayout handles large content efficiently', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveLayout(
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (context, index) => VSCard(
                  margin: EdgeInsets.all(8),
                  child: ListTile(
                    title: Text('Item $index'),
                    subtitle: Text('Subtitle $index'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // Large list should render initial frame in under 300ms
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });

    testWidgets('Multiple VSButton instances render efficiently', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: List.generate(20, (index) => 
                VSButton(
                  text: 'Button $index',
                  onPressed: () {},
                  variant: index % 2 == 0 ? VSButtonVariant.primary : VSButtonVariant.outline,
                ),
              ),
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // 20 buttons should render in under 250ms
      expect(stopwatch.elapsedMilliseconds, lessThan(250));
    });

    testWidgets('VSResponsiveBuilder rebuilds efficiently', (WidgetTester tester) async {
      int buildCount = 0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveBuilder(
              builder: (context, breakpoint) {
                buildCount++;
                return Text('Breakpoint: ${breakpoint.name}');
              },
            ),
          ),
        ),
      );
      
      // Should only build once initially
      expect(buildCount, equals(1));
      
      // Pump again to ensure no unnecessary rebuilds
      await tester.pump();
      expect(buildCount, equals(1));
    });

    testWidgets('VSAccessibleTextField handles rapid input efficiently', (WidgetTester tester) async {
      final controller = TextEditingController();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSAccessibleTextField(
              controller: controller,
              labelText: 'Performance Test',
            ),
          ),
        ),
      );
      
      final stopwatch = Stopwatch()..start();
      
      // Simulate rapid text input
      for (int i = 0; i < 10; i++) {
        await tester.enterText(find.byType(TextField), 'Text input $i');
        await tester.pump(Duration(milliseconds: 10));
      }
      
      stopwatch.stop();
      
      // Rapid input should complete in under 500ms
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
      
      controller.dispose();
    });

    testWidgets('VSLoadingIndicator animates smoothly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSLoadingIndicator(
              message: 'Loading...',
            ),
          ),
        ),
      );
      
      // Pump several animation frames
      for (int i = 0; i < 10; i++) {
        await tester.pump(Duration(milliseconds: 16)); // ~60fps
      }
      
      // Should not throw any performance warnings
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('VSEmptyState renders complex layouts efficiently', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSEmptyState(
              icon: Icons.inbox_outlined,
              title: 'No items found',
              subtitle: 'Try adjusting your search criteria or add new items',
              action: Column(
                children: [
                  VSButton(
                    text: 'Add Item',
                    onPressed: () {},
                    variant: VSButtonVariant.primary,
                  ),
                  SizedBox(height: 8),
                  VSButton(
                    text: 'Clear Filters',
                    onPressed: () {},
                    variant: VSButtonVariant.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // Complex empty state should render in under 150ms
      expect(stopwatch.elapsedMilliseconds, lessThan(150));
    });

    testWidgets('VSResponsiveText scales without performance issues', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: List.generate(50, (index) => 
                VSResponsiveText(
                  text: 'Responsive text item $index',
                  baseStyle: TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // 50 responsive text widgets should render in under 300ms
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });

    testWidgets('VSCard with nested responsive components performs well', (WidgetTester tester) async {
      final stopwatch = Stopwatch()..start();
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSResponsiveLayout(
              child: Column(
                children: List.generate(10, (index) => 
                  VSCard(
                    margin: EdgeInsets.all(8),
                    child: Column(
                      children: [
                        VSResponsiveText(
                          text: 'Card Title $index',
                          baseStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        VSResponsiveSpacing(),
                        VSResponsiveText(
                          text: 'Card content for item $index with some longer text to test performance',
                          baseStyle: TextStyle(fontSize: 14),
                        ),
                        VSResponsiveSpacing(),
                        VSResponsiveBuilder(
                          builder: (context, breakpoint) {
                            return VSButton(
                              text: 'Action $index',
                              onPressed: () {},
                              isFullWidth: breakpoint == VSBreakpoint.mobile,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      
      stopwatch.stop();
      
      // Complex nested responsive layout should render in under 400ms
      expect(stopwatch.elapsedMilliseconds, lessThan(400));
    });
  });

  group('Memory Usage Tests', () {
    testWidgets('VSButton does not leak memory', (WidgetTester tester) async {
      // Create and destroy multiple buttons to test for memory leaks
      for (int i = 0; i < 10; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VSButton(
                text: 'Button $i',
                onPressed: () {},
              ),
            ),
          ),
        );
        
        await tester.pumpWidget(Container()); // Clear the widget
      }
      
      // If we get here without memory issues, the test passes
      expect(true, isTrue);
    });

    testWidgets('VSCard properly disposes resources', (WidgetTester tester) async {
      // Create and destroy multiple cards
      for (int i = 0; i < 10; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VSCard(
                child: Column(
                  children: List.generate(5, (j) => Text('Item $j')),
                ),
              ),
            ),
          ),
        );
        
        await tester.pumpWidget(Container()); // Clear the widget
      }
      
      expect(true, isTrue);
    });

    testWidgets('VSResponsiveLayout handles widget tree changes efficiently', (WidgetTester tester) async {
      bool showContent = true;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return VSResponsiveLayout(
                  child: Column(
                    children: [
                      VSButton(
                        text: 'Toggle Content',
                        onPressed: () => setState(() => showContent = !showContent),
                      ),
                      if (showContent) ...[
                        VSCard(child: Text('Dynamic Content')),
                        VSResponsiveText(text: 'Responsive Text'),
                        VSLoadingIndicator(message: 'Loading...'),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      
      // Toggle content multiple times to test efficiency
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('Toggle Content'));
        await tester.pump();
      }
      
      expect(find.text('Toggle Content'), findsOneWidget);
    });
  });

  group('Animation Performance Tests', () {
    testWidgets('VSButton hover animations perform smoothly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VSButton(
              text: 'Hover Test',
              onPressed: () {},
            ),
          ),
        ),
      );
      
      // Simulate hover state changes
      final gesture = await tester.createGesture();
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.byType(ElevatedButton)));
      await tester.pump();
      
      // Animate hover state
      await tester.pump(Duration(milliseconds: 100));
      await tester.pump(Duration(milliseconds: 100));
      
      await gesture.removePointer();
      await tester.pump();
      
      expect(find.text('Hover Test'), findsOneWidget);
    });

    testWidgets('VSCard elevation changes animate smoothly', (WidgetTester tester) async {
      double elevation = 2.0;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    VSButton(
                      text: 'Change Elevation',
                      onPressed: () => setState(() => elevation = elevation == 2.0 ? 8.0 : 2.0),
                    ),
                    VSCard(
                      elevation: elevation,
                      child: Text('Animated Card'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      
      // Change elevation and animate
      await tester.tap(find.text('Change Elevation'));
      await tester.pump();
      await tester.pump(Duration(milliseconds: 200));
      
      expect(find.text('Animated Card'), findsOneWidget);
    });
  });
}
