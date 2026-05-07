import 'package:flutter_test/flutter_test.dart';

import 'main_test.dart' as main_tests;
import 'shared/connectivity_service_test.dart' as connectivity_tests;
import 'shared/utils/snackbar_utils_test.dart' as snackbar_tests;
import 'shared/notifiers/subscription_status_notifier_test.dart' as notifier_tests;
import 'design_system/vs_components_test.dart' as vs_components_test;
import 'performance/performance_test.dart' as performance_test;

void main() {
  group('VisionSpark App Tests', () {
    group('Main App Tests', main_tests.main);
    group('Connectivity Tests', connectivity_tests.main);
    group('Snackbar Utils Tests', snackbar_tests.main);
    group('Notifier Tests', notifier_tests.main);
    group('Design System Tests', vs_components_test.main);
    group('Performance Tests', performance_test.main);
  });
}
