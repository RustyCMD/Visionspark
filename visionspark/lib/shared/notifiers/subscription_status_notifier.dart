import 'package:flutter/foundation.dart';

class SubscriptionStatusNotifier extends ChangeNotifier {
  void subscriptionChanged() {
    notifyListeners();
  }
} 