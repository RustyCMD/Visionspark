# VisionSpark Tests

This directory contains comprehensive unit tests for the VisionSpark Flutter application.

## Test Structure

The tests are organized by feature and component type:

### Core App Tests
- `main_test.dart` - Tests for main app initialization, theme controller, and app configuration
- `test_runner.dart` - Aggregated test runner for all test suites

### Authentication Tests
- `auth/auth_gate_test.dart` - Tests for authentication state management and routing

### Shared Components Tests
- `shared/connectivity_service_test.dart` - Network connectivity handling tests
- `shared/utils/snackbar_utils_test.dart` - Snackbar utility function tests
- `shared/notifiers/subscription_status_notifier_test.dart` - Subscription status notifier tests

### Feature Tests
- `features/image_generator/image_generator_test.dart` - Image generation functionality tests
- `features/gallery/gallery_test.dart` - Gallery display and interaction tests
- `features/account/account_test.dart` - Account management and profile tests

## Test Coverage

The test suite covers:

### Widget Tests
- UI component rendering and interaction
- User input handling
- State management
- Error state handling
- Loading states

### Unit Tests
- Business logic validation
- Data transformations
- Utility functions
- State calculations
- Input validation

### Integration-style Tests
- API mocking and responses
- Database operations simulation
- Authentication flows
- File operations

## Running Tests

### Prerequisites

1. Install dependencies:
```bash
cd visionspark
flutter pub get
```

2. Generate mock files:
```bash
flutter packages pub run build_runner build
```

### Running All Tests

Run the complete test suite:
```bash
flutter test
```

### Running Specific Test Files

Run tests for a specific feature:
```bash
flutter test test/features/image_generator/image_generator_test.dart
flutter test test/features/gallery/gallery_test.dart
flutter test test/features/account/account_test.dart
```

Run tests for shared components:
```bash
flutter test test/shared/connectivity_service_test.dart
flutter test test/shared/utils/snackbar_utils_test.dart
```

### Running with Coverage

Generate test coverage report:
```bash
flutter test --coverage
```

View coverage in browser:
```bash
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

## Test Patterns

### Mocking
Tests use the `mockito` package to mock external dependencies:
- Supabase client and services
- Network requests
- File system operations
- Platform-specific APIs

### Widget Testing
Widget tests follow these patterns:
- Create test widgets with necessary providers
- Pump widgets and allow settling
- Test user interactions and state changes
- Verify UI elements and behaviors

### State Testing
State management tests verify:
- Initial states
- State transitions
- Listener notifications
- Error handling
- Cleanup and disposal

## Test Utilities

### Common Mocks
- `MockSupabaseClient` - For database and auth operations
- `MockConnectivity` - For network state simulation
- `MockSharedPreferences` - For local storage testing

### Test Helpers
- `createTestWidget()` - Standard widget wrapper with providers
- Mock data factories for consistent test data
- Async operation testing with completers and futures

## Best Practices

1. **Isolation**: Each test is independent and doesn't rely on other tests
2. **Mocking**: External dependencies are mocked to ensure unit test isolation
3. **Coverage**: Tests cover both happy paths and error scenarios
4. **Readability**: Test names clearly describe what is being tested
5. **Maintainability**: Tests are organized logically and use shared utilities

## Adding New Tests

When adding new features:

1. Create test files following the existing directory structure
2. Use appropriate mocking for external dependencies
3. Test both UI components and business logic
4. Include error scenarios and edge cases
5. Update `test_runner.dart` to include new test suites

## Mock Generation

The project uses `mockito` for generating mocks. When adding new classes to mock:

1. Add `@GenerateMocks([ClassName])` annotation
2. Run `flutter packages pub run build_runner build`
3. Import generated mocks: `import 'test_file.mocks.dart'`

## Continuous Integration

These tests are designed to run in CI/CD pipelines:
- No external dependencies required
- Deterministic test results
- Fast execution with proper mocking
- Clear pass/fail indicators