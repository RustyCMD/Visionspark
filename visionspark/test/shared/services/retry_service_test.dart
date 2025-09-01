import 'package:flutter_test/flutter_test.dart';
import 'package:visionspark/shared/services/retry_service.dart';

void main() {
  group('RetryService Tests', () {
    late RetryService retryService;

    setUp(() {
      retryService = RetryService();
    });

    group('Successful Operations', () {
      test('should succeed on first attempt', () async {
        int callCount = 0;
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            return 'success';
          },
          operationType: RetryOperationType.networkRequest,
        );

        expect(result.success, true);
        expect(result.data, 'success');
        expect(result.attempts, 1);
        expect(callCount, 1);
      });

      test('should succeed after retries', () async {
        int callCount = 0;
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            if (callCount < 3) {
              throw Exception('Network timeout');
            }
            return 'success after retries';
          },
          operationType: RetryOperationType.networkRequest,
        );

        expect(result.success, true);
        expect(result.data, 'success after retries');
        expect(result.attempts, 3);
        expect(callCount, 3);
      });
    });

    group('Failed Operations', () {
      test('should fail after max retries with retryable error', () async {
        int callCount = 0;
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            throw Exception('Network timeout');
          },
          operationType: RetryOperationType.networkRequest,
        );

        expect(result.success, false);
        expect(result.data, null);
        expect(result.attempts, 3); // Default max retries for network request
        expect(result.wasRetryable, true);
        expect(result.error, contains('Network timeout'));
        expect(callCount, 3);
      });

      test('should fail immediately with non-retryable error', () async {
        int callCount = 0;
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            throw Exception('Invalid input');
          },
          operationType: RetryOperationType.networkRequest,
        );

        expect(result.success, false);
        expect(result.data, null);
        expect(result.attempts, 1);
        expect(result.wasRetryable, false);
        expect(result.error, contains('Invalid input'));
        expect(callCount, 1);
      });
    });

    group('Retry Configuration', () {
      test('should respect custom retry config', () async {
        int callCount = 0;
        const customConfig = RetryConfig(
          maxRetries: 5,
          baseDelay: Duration(milliseconds: 10),
          useJitter: false,
        );
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            throw Exception('Connection failed');
          },
          operationType: RetryOperationType.networkRequest,
          customConfig: customConfig,
        );

        expect(result.success, false);
        expect(result.attempts, 5);
        expect(callCount, 5);
      });

      test('should respect max total wait time', () async {
        int callCount = 0;
        const customConfig = RetryConfig(
          maxRetries: 10,
          maxTotalWait: Duration(milliseconds: 50),
          baseDelay: Duration(milliseconds: 20),
          useJitter: false,
        );
        
        final stopwatch = Stopwatch()..start();
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            throw Exception('Timeout error');
          },
          operationType: RetryOperationType.networkRequest,
          customConfig: customConfig,
        );
        
        stopwatch.stop();

        expect(result.success, false);
        expect(callCount, lessThan(10)); // Should stop before max retries due to time limit
        expect(stopwatch.elapsedMilliseconds, lessThan(200)); // Should respect time limit
      });
    });

    group('Error Classification', () {
      test('should classify network errors as retryable', () async {
        final networkErrors = [
          'Network timeout',
          'Connection failed',
          'Socket exception',
          'Handshake failed',
          'HTTP 500 error',
          'HTTP 502 error',
          'HTTP 503 error',
          'HTTP 504 error',
          'HTTP 429 error',
        ];

        for (final errorMessage in networkErrors) {
          int callCount = 0;
          
          final result = await retryService.execute<String>(
            operation: () async {
              callCount++;
              throw Exception(errorMessage);
            },
            operationType: RetryOperationType.networkRequest,
          );

          expect(result.wasRetryable, true, reason: 'Error "$errorMessage" should be retryable');
          expect(callCount, greaterThan(1), reason: 'Error "$errorMessage" should trigger retries');
        }
      });

      test('should classify application errors as non-retryable', () async {
        final nonRetryableErrors = [
          'Invalid input',
          'Authentication failed',
          'Permission denied',
          'Resource not found',
          'Bad request',
        ];

        for (final errorMessage in nonRetryableErrors) {
          int callCount = 0;
          
          final result = await retryService.execute<String>(
            operation: () async {
              callCount++;
              throw Exception(errorMessage);
            },
            operationType: RetryOperationType.networkRequest,
          );

          expect(result.wasRetryable, false, reason: 'Error "$errorMessage" should not be retryable');
          expect(callCount, 1, reason: 'Error "$errorMessage" should not trigger retries');
        }
      });
    });

    group('Operation Types', () {
      test('should use correct config for subscription status', () async {
        int callCount = 0;
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            throw Exception('Network timeout');
          },
          operationType: RetryOperationType.subscriptionStatus,
        );

        expect(result.attempts, 8); // Default max retries for subscription status
        expect(callCount, 8);
      });

      test('should use correct config for image generation', () async {
        int callCount = 0;
        
        final result = await retryService.execute<String>(
          operation: () async {
            callCount++;
            throw Exception('Network timeout');
          },
          operationType: RetryOperationType.imageGeneration,
        );

        expect(result.attempts, 3); // Default max retries for image generation
        expect(callCount, 3);
      });
    });

    group('Progress Callbacks', () {
      test('should call progress callback on each attempt', () async {
        final progressCalls = <Map<String, int>>[];
        
        await retryService.execute<String>(
          operation: () async {
            throw Exception('Network timeout');
          },
          operationType: RetryOperationType.networkRequest,
          onProgress: (attempt, maxAttempts, elapsed) {
            progressCalls.add({
              'attempt': attempt,
              'maxAttempts': maxAttempts,
            });
          },
        );

        expect(progressCalls.length, 3); // Should be called for each attempt
        expect(progressCalls[0]['attempt'], 1);
        expect(progressCalls[1]['attempt'], 2);
        expect(progressCalls[2]['attempt'], 3);
        expect(progressCalls.every((call) => call['maxAttempts'] == 3), true);
      });
    });

    group('Future Extension', () {
      test('should work with Future extension', () async {
        int callCount = 0;
        
        final result = await Future<String>(() async {
          callCount++;
          if (callCount < 2) {
            throw Exception('Network timeout');
          }
          return 'success';
        }).withRetry(
          operationType: RetryOperationType.networkRequest,
        );

        expect(result.success, true);
        expect(result.data, 'success');
        expect(result.attempts, 2);
        expect(callCount, 2);
      });
    });
  });

  group('RetryConfig Tests', () {
    test('should create correct config for each operation type', () {
      final subscriptionConfig = RetryConfig.forOperation(RetryOperationType.subscriptionStatus);
      expect(subscriptionConfig.maxRetries, 8);
      expect(subscriptionConfig.maxTotalWait, const Duration(minutes: 2));

      final imageConfig = RetryConfig.forOperation(RetryOperationType.imageGeneration);
      expect(imageConfig.maxRetries, 3);
      expect(imageConfig.maxTotalWait, const Duration(seconds: 30));

      final networkConfig = RetryConfig.forOperation(RetryOperationType.networkRequest);
      expect(networkConfig.maxRetries, 3);
      expect(networkConfig.maxTotalWait, const Duration(seconds: 15));
    });
  });

  group('RetryResult Tests', () {
    test('should create successful result correctly', () {
      const result = RetryResult<String>(
        data: 'test data',
        success: true,
        attempts: 2,
        totalTime: Duration(seconds: 5),
      );

      expect(result.success, true);
      expect(result.data, 'test data');
      expect(result.attempts, 2);
      expect(result.totalTime, const Duration(seconds: 5));
      expect(result.error, null);
      expect(result.wasRetryable, false);
    });

    test('should create failed result correctly', () {
      const result = RetryResult<String>(
        success: false,
        attempts: 3,
        totalTime: Duration(seconds: 10),
        error: 'Network timeout',
        wasRetryable: true,
      );

      expect(result.success, false);
      expect(result.data, null);
      expect(result.attempts, 3);
      expect(result.totalTime, const Duration(seconds: 10));
      expect(result.error, 'Network timeout');
      expect(result.wasRetryable, true);
    });
  });
}
