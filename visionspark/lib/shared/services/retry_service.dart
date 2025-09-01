import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Enum for different types of operations that may need retry logic
enum RetryOperationType {
  subscriptionStatus('Subscription Status', 8, Duration(minutes: 2)),
  purchaseValidation('Purchase Validation', 5, Duration(minutes: 1)),
  imageGeneration('Image Generation', 3, Duration(seconds: 30)),
  imageEnhancement('Image Enhancement', 3, Duration(seconds: 30)),
  profileUpdate('Profile Update', 5, Duration(minutes: 1)),
  networkRequest('Network Request', 3, Duration(seconds: 15));

  const RetryOperationType(this.displayName, this.defaultMaxRetries, this.defaultMaxTotalWait);

  final String displayName;
  final int defaultMaxRetries;
  final Duration defaultMaxTotalWait;
}

/// Configuration for retry behavior
class RetryConfig {
  final int maxRetries;
  final Duration maxTotalWait;
  final Duration baseDelay;
  final double backoffMultiplier;
  final Duration maxDelay;
  final bool useJitter;
  final List<Type> retryableExceptions;

  const RetryConfig({
    this.maxRetries = 3,
    this.maxTotalWait = const Duration(minutes: 1),
    this.baseDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(seconds: 30),
    this.useJitter = true,
    this.retryableExceptions = const [],
  });

  /// Create a config for a specific operation type
  factory RetryConfig.forOperation(RetryOperationType type) {
    switch (type) {
      case RetryOperationType.subscriptionStatus:
        return const RetryConfig(
          maxRetries: 8,
          maxTotalWait: Duration(minutes: 2),
          baseDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          maxDelay: Duration(seconds: 30),
          useJitter: true,
        );
      case RetryOperationType.purchaseValidation:
        return const RetryConfig(
          maxRetries: 5,
          maxTotalWait: Duration(minutes: 1),
          baseDelay: Duration(milliseconds: 1500),
          backoffMultiplier: 1.8,
          maxDelay: Duration(seconds: 20),
          useJitter: true,
        );
      case RetryOperationType.imageGeneration:
      case RetryOperationType.imageEnhancement:
        return const RetryConfig(
          maxRetries: 3,
          maxTotalWait: Duration(seconds: 30),
          baseDelay: Duration(seconds: 2),
          backoffMultiplier: 1.5,
          maxDelay: Duration(seconds: 10),
          useJitter: false,
        );
      case RetryOperationType.profileUpdate:
        return const RetryConfig(
          maxRetries: 5,
          maxTotalWait: Duration(minutes: 1),
          baseDelay: Duration(seconds: 1),
          backoffMultiplier: 2.0,
          maxDelay: Duration(seconds: 15),
          useJitter: true,
        );
      case RetryOperationType.networkRequest:
        return const RetryConfig(
          maxRetries: 3,
          maxTotalWait: Duration(seconds: 15),
          baseDelay: Duration(milliseconds: 500),
          backoffMultiplier: 2.0,
          maxDelay: Duration(seconds: 5),
          useJitter: true,
        );
    }
  }
}

/// Result of a retry operation
class RetryResult<T> {
  final T? data;
  final bool success;
  final int attempts;
  final Duration totalTime;
  final String? error;
  final bool wasRetryable;

  const RetryResult({
    this.data,
    required this.success,
    required this.attempts,
    required this.totalTime,
    this.error,
    this.wasRetryable = false,
  });
}

/// Progress callback for retry operations
typedef RetryProgressCallback = void Function(int currentAttempt, int maxAttempts, Duration elapsed);

/// Standardized retry service for consistent retry behavior across the app
class RetryService {
  static final RetryService _instance = RetryService._internal();
  factory RetryService() => _instance;
  RetryService._internal();

  /// Execute an operation with retry logic
  Future<RetryResult<T>> execute<T>({
    required Future<T> Function() operation,
    required RetryOperationType operationType,
    RetryConfig? customConfig,
    RetryProgressCallback? onProgress,
    String? operationName,
    Map<String, dynamic>? context,
  }) async {
    final config = customConfig ?? RetryConfig.forOperation(operationType);
    final name = operationName ?? operationType.displayName;
    final startTime = DateTime.now();
    
    if (kDebugMode) {
      print('🔄 Starting retry operation: $name (max ${config.maxRetries} attempts, max ${config.maxTotalWait.inSeconds}s)');
    }

    Exception? lastException;
    
    for (int attempt = 1; attempt <= config.maxRetries; attempt++) {
      // Check if we've exceeded the maximum total wait time
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed > config.maxTotalWait) {
        if (kDebugMode) {
          print('⏰ Maximum total wait time exceeded for $name (${elapsed.inSeconds}s)');
        }
        break;
      }

      try {
        if (kDebugMode) {
          print('🔄 Attempt $attempt/${ config.maxRetries} for $name');
        }
        
        // Call progress callback
        onProgress?.call(attempt, config.maxRetries, elapsed);
        
        final result = await operation();
        
        final totalTime = DateTime.now().difference(startTime);
        if (kDebugMode) {
          print('✅ $name succeeded on attempt $attempt (${totalTime.inMilliseconds}ms)');
        }
        
        return RetryResult<T>(
          data: result,
          success: true,
          attempts: attempt,
          totalTime: totalTime,
        );
      } catch (error) {
        lastException = error is Exception ? error : Exception(error.toString());
        
        if (kDebugMode) {
          print('❌ $name failed on attempt $attempt: $error');
        }
        
        // Check if this error is retryable
        final isRetryable = _isRetryableError(error, config);
        
        // If not retryable or this is the last attempt, don't retry
        if (!isRetryable || attempt == config.maxRetries) {
          final totalTime = DateTime.now().difference(startTime);
          if (kDebugMode) {
            print('🚫 $name failed permanently after $attempt attempts (${totalTime.inMilliseconds}ms)');
          }
          
          return RetryResult<T>(
            success: false,
            attempts: attempt,
            totalTime: totalTime,
            error: error.toString(),
            wasRetryable: isRetryable,
          );
        }
        
        // Calculate delay for next attempt
        final delay = _calculateDelay(attempt, config);
        
        if (kDebugMode) {
          print('⏳ Waiting ${delay.inMilliseconds}ms before retry ${attempt + 1} for $name');
        }
        
        await Future.delayed(delay);
      }
    }
    
    // This should rarely be reached, but handle it gracefully
    final totalTime = DateTime.now().difference(startTime);
    return RetryResult<T>(
      success: false,
      attempts: config.maxRetries,
      totalTime: totalTime,
      error: lastException?.toString() ?? 'Maximum retries exceeded',
      wasRetryable: true,
    );
  }

  /// Check if an error is retryable based on the configuration and error type
  bool _isRetryableError(dynamic error, RetryConfig config) {
    // If specific retryable exceptions are configured, check against them
    if (config.retryableExceptions.isNotEmpty) {
      return config.retryableExceptions.any((type) => error.runtimeType == type);
    }
    
    // Default retryable error patterns
    final errorString = error.toString().toLowerCase();
    
    // Network-related errors are generally retryable
    if (errorString.contains('timeout') ||
        errorString.contains('connection') ||
        errorString.contains('network') ||
        errorString.contains('socket') ||
        errorString.contains('handshake')) {
      return true;
    }
    
    // HTTP status codes that are retryable
    if (errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504') ||
        errorString.contains('429')) {
      return true;
    }
    
    // Temporary failures
    if (errorString.contains('temporary') ||
        errorString.contains('unavailable') ||
        errorString.contains('busy')) {
      return true;
    }
    
    // Default to non-retryable for unknown errors
    return false;
  }

  /// Calculate delay for the next retry attempt
  Duration _calculateDelay(int attempt, RetryConfig config) {
    // Calculate exponential backoff
    final baseDelayMs = config.baseDelay.inMilliseconds;
    final exponentialDelay = baseDelayMs * pow(config.backoffMultiplier, attempt - 1);
    
    // Apply jitter if enabled
    double finalDelay = exponentialDelay.toDouble();
    if (config.useJitter) {
      final jitterRange = finalDelay * 0.1; // 10% jitter
      final jitter = (Random().nextDouble() - 0.5) * 2 * jitterRange;
      finalDelay += jitter;
    }
    
    // Cap at maximum delay
    final cappedDelay = finalDelay.clamp(0, config.maxDelay.inMilliseconds.toDouble());
    
    return Duration(milliseconds: cappedDelay.round());
  }
}

/// Extension to add retry functionality to Future operations
extension FutureRetry<T> on Future<T> {
  /// Add retry logic to any Future operation
  Future<RetryResult<T>> withRetry({
    required RetryOperationType operationType,
    RetryConfig? config,
    RetryProgressCallback? onProgress,
    String? operationName,
  }) {
    return RetryService().execute<T>(
      operation: () => this,
      operationType: operationType,
      customConfig: config,
      onProgress: onProgress,
      operationName: operationName,
    );
  }
}
