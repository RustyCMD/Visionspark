import 'package:flutter/foundation.dart';
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
      expect(notifier.activeSubscriptionType, isNull);
      expect(notifier.isLoading, false);
      expect(notifier.hasActiveSubscription, false);
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
      bool notified = false;
      void listener() {
        notified = true;
      }

      notifier.addListener(listener);
      notifier.subscriptionChanged();
      expect(notified, true);

      notified = false;
      notifier.removeListener(listener);
      notifier.subscriptionChanged();
      expect(notified, false);
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
      bool notified1 = false;
      bool notified2 = false;

      void listener1() { notified1 = true; }
      void listener2() { notified2 = true; }

      notifier.addListener(listener1);
      notifier.addListener(listener2);

      // Verify listeners are working before dispose
      notifier.subscriptionChanged();
      expect(notified1, true);
      expect(notified2, true);

      notifier.dispose();

      // After dispose, calling notifyListeners should not crash
      expect(() => notifier.subscriptionChanged(), returnsNormally);
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