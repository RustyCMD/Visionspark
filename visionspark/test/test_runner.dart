import 'package:flutter_test/flutter_test.dart';

// Import all test files
import 'main_test.dart' as main_tests;
import 'auth/auth_gate_test.dart' as auth_gate_tests;
import 'shared/connectivity_service_test.dart' as connectivity_tests;
import 'shared/utils/snackbar_utils_test.dart' as snackbar_tests;
import 'shared/notifiers/subscription_status_notifier_test.dart' as notifier_tests;
import 'features/image_generator/image_generator_test.dart' as image_generator_tests;
import 'features/gallery/gallery_test.dart' as gallery_tests;
import 'features/account/account_test.dart' as account_tests;

void main() {
  group('VisionSpark App Tests', () {
    group('Main App Tests', main_tests.main);
    group('Authentication Tests', auth_gate_tests.main);
    group('Connectivity Tests', connectivity_tests.main);
    group('Snackbar Utils Tests', snackbar_tests.main);
    group('Notifier Tests', notifier_tests.main);
    group('Image Generator Tests', image_generator_tests.main);
    group('Gallery Tests', gallery_tests.main);
    group('Account Tests', account_tests.main);
  });
}