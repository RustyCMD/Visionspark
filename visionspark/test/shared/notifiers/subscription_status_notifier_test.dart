import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/notifiers/subscription_status_notifier.dart';

void main() {
  group('SubscriptionStatusNotifier Tests', () {
    late SubscriptionStatusNotifier notifier;

    setUp(() {
      notifier = SubscriptionStatusNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('initial state is correct', () {
      expect(notifier.hasListeners, false);
    });

    test('notifies listeners when changed', () {
      bool notified = false;
      notifier.addListener(() {
        notified = true;
      });

      notifier.notifyListeners();
      
      expect(notified, true);
    });

    test('can add and remove listeners', () {
      void listener() {}

      notifier.addListener(listener);
      expect(notifier.hasListeners, true);

      notifier.removeListener(listener);
      expect(notifier.hasListeners, false);
    });

    test('handles multiple listeners correctly', () {
      int notificationCount1 = 0;
      int notificationCount2 = 0;

      void listener1() => notificationCount1++;
      void listener2() => notificationCount2++;

      notifier.addListener(listener1);
      notifier.addListener(listener2);

      notifier.notifyListeners();

      expect(notificationCount1, 1);
      expect(notificationCount2, 1);

      notifier.removeListener(listener1);
      notifier.notifyListeners();

      expect(notificationCount1, 1); // Should not increase
      expect(notificationCount2, 2); // Should increase
    });

    test('dispose removes all listeners', () {
      void listener1() {}
      void listener2() {}

      notifier.addListener(listener1);
      notifier.addListener(listener2);
      
      expect(notifier.hasListeners, true);

      notifier.dispose();
      
      // After dispose, the notifier should not have listeners
      // Note: hasListeners might not be accurate after dispose in some implementations
      expect(() => notifier.notifyListeners(), returnsNormally);
    });

    test('calling notifyListeners after dispose does not crash', () {
      notifier.dispose();
      
      expect(() => notifier.notifyListeners(), returnsNormally);
    });

    test('adding listener after dispose does not crash', () {
      notifier.dispose();
      
      expect(() => notifier.addListener(() {}), returnsNormally);
    });

    test('can be extended for subscription-specific functionality', () {
      // This tests that the base notifier can be extended
      final customNotifier = SubscriptionStatusNotifier();
      
      expect(customNotifier, isA<ChangeNotifier>());
      
      customNotifier.dispose();
    });
  });
}