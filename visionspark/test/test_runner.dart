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

// Import UI/UX test files
import 'design_system/vs_components_test.dart' as vs_components_test;
import 'accessibility/accessibility_test.dart' as accessibility_test;
import 'integration/screen_integration_test.dart' as screen_integration_test;
import 'performance/performance_test.dart' as performance_test;

void main() {
  group('VisionSpark App Tests', () {
    // Core functionality tests
    group('Main App Tests', main_tests.main);
    group('Authentication Tests', auth_gate_tests.main);
    group('Connectivity Tests', connectivity_tests.main);
    group('Snackbar Utils Tests', snackbar_tests.main);
    group('Notifier Tests', notifier_tests.main);
    group('Image Generator Tests', image_generator_tests.main);
    group('Gallery Tests', gallery_tests.main);
    group('Account Tests', account_tests.main);

    // UI/UX improvement tests
    group('🎨 Design System Tests', vs_components_test.main);
    group('♿ Accessibility Tests', accessibility_test.main);
    group('🔗 Integration Tests', screen_integration_test.main);
    group('⚡ Performance Tests', performance_test.main);
  });
}