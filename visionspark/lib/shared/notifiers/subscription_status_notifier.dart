import 'package:flutter/foundation.dart';

class SubscriptionStatusNotifier extends ChangeNotifier {
  String? _activeSubscriptionType;
  bool _isLoading = false;

  String? get activeSubscriptionType => _activeSubscriptionType;
  bool get isLoading => _isLoading;
  bool get hasActiveSubscription => _activeSubscriptionType != null;

  void subscriptionChanged() {
    debugPrint('🔔 SubscriptionStatusNotifier: Subscription status changed');
    notifyListeners();
  }

  void updateSubscriptionStatus(String? subscriptionType) {
    if (_activeSubscriptionType != subscriptionType) {
      _activeSubscriptionType = subscriptionType;
      debugPrint('🔄 SubscriptionStatusNotifier: Updated subscription type to: $subscriptionType');
      notifyListeners();
    }
  }

  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void forceRefresh() {
    debugPrint('🔄 SubscriptionStatusNotifier: Force refresh requested');
    notifyListeners();
  }
}