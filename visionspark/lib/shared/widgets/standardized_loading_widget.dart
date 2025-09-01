import 'package:flutter/material.dart';
import '../design_system/design_system.dart';
import '../services/retry_service.dart';

/// Standardized loading widget that works with the retry service
class StandardizedLoadingWidget extends StatelessWidget {
  final RetryOperationType operationType;
  final int currentAttempt;
  final int maxAttempts;
  final Duration elapsed;
  final String? customMessage;
  final bool showProgress;
  final bool showAttemptCounter;
  final bool showElapsedTime;
  final VoidCallback? onCancel;

  const StandardizedLoadingWidget({
    super.key,
    required this.operationType,
    this.currentAttempt = 1,
    this.maxAttempts = 1,
    this.elapsed = Duration.zero,
    this.customMessage,
    this.showProgress = true,
    this.showAttemptCounter = true,
    this.showElapsedTime = false,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return VSCard(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      elevation: VSDesignTokens.elevation1,
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Loading indicator
          VSLoadingIndicator(
            message: _getLoadingMessage(),
            size: VSDesignTokens.iconL,
          ),
          
          if (showProgress && maxAttempts > 1) ...[
            const SizedBox(height: VSDesignTokens.space3),
            LinearProgressIndicator(
              value: currentAttempt / maxAttempts,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ],
          
          if (showAttemptCounter && maxAttempts > 1) ...[
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              'Attempt $currentAttempt of $maxAttempts',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: VSTypography.weightMedium,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          if (showElapsedTime && elapsed.inSeconds > 0) ...[
            const SizedBox(height: VSDesignTokens.space1),
            Text(
              'Elapsed: ${_formatDuration(elapsed)}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          if (onCancel != null) ...[
            const SizedBox(height: VSDesignTokens.space3),
            VSButton(
              text: 'Cancel',
              onPressed: onCancel,
              variant: VSButtonVariant.outline,
              size: VSButtonSize.small,
            ),
          ],
        ],
      ),
    );
  }

  String _getLoadingMessage() {
    if (customMessage != null) return customMessage!;
    
    switch (operationType) {
      case RetryOperationType.subscriptionStatus:
        if (currentAttempt > 1) {
          return 'Checking subscription status... (retry $currentAttempt)';
        }
        return 'Checking subscription status...';
      case RetryOperationType.purchaseValidation:
        if (currentAttempt > 1) {
          return 'Validating purchase... (retry $currentAttempt)';
        }
        return 'Validating your purchase...';
      case RetryOperationType.imageGeneration:
        if (currentAttempt > 1) {
          return 'Generating image... (retry $currentAttempt)';
        }
        return 'Generating your image...';
      case RetryOperationType.imageEnhancement:
        if (currentAttempt > 1) {
          return 'Enhancing image... (retry $currentAttempt)';
        }
        return 'Enhancing your image...';
      case RetryOperationType.profileUpdate:
        if (currentAttempt > 1) {
          return 'Updating profile... (retry $currentAttempt)';
        }
        return 'Updating your profile...';
      case RetryOperationType.networkRequest:
        if (currentAttempt > 1) {
          return 'Processing request... (retry $currentAttempt)';
        }
        return 'Processing your request...';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
    return '${duration.inSeconds}s';
  }
}

/// Standardized error widget that works with retry results
class StandardizedErrorWidget extends StatelessWidget {
  final RetryResult result;
  final RetryOperationType operationType;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final String? customMessage;

  const StandardizedErrorWidget({
    super.key,
    required this.result,
    required this.operationType,
    this.onRetry,
    this.onCancel,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return VSCard(
      color: colorScheme.errorContainer.withValues(alpha: 0.3),
      elevation: VSDesignTokens.elevation2,
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            result.wasRetryable ? Icons.refresh : Icons.error_outline,
            size: VSDesignTokens.iconL,
            color: colorScheme.error,
          ),
          
          const SizedBox(height: VSDesignTokens.space3),
          
          Text(
            _getErrorTitle(),
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onErrorContainer,
              fontWeight: VSTypography.weightBold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: VSDesignTokens.space2),
          
          Text(
            customMessage ?? _getErrorMessage(),
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onErrorContainer,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: VSDesignTokens.space2),
          
          Text(
            'Attempted ${result.attempts} time${result.attempts > 1 ? 's' : ''} over ${_formatDuration(result.totalTime)}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onErrorContainer.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: VSDesignTokens.space4),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onCancel != null) ...[
                VSButton(
                  text: 'Cancel',
                  onPressed: onCancel,
                  variant: VSButtonVariant.outline,
                  size: VSButtonSize.medium,
                ),
                if (onRetry != null && result.wasRetryable) 
                  const SizedBox(width: VSDesignTokens.space3),
              ],
              
              if (onRetry != null && result.wasRetryable) ...[
                VSButton(
                  text: 'Try Again',
                  onPressed: onRetry,
                  variant: VSButtonVariant.primary,
                  size: VSButtonSize.medium,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _getErrorTitle() {
    if (result.wasRetryable) {
      return '${operationType.displayName} Failed';
    }
    return '${operationType.displayName} Error';
  }

  String _getErrorMessage() {
    if (result.wasRetryable) {
      return 'We tried multiple times but couldn\'t complete the operation. This might be due to a temporary network issue.';
    }
    
    switch (operationType) {
      case RetryOperationType.subscriptionStatus:
        return 'Unable to check your subscription status. Please check your internet connection and try again.';
      case RetryOperationType.purchaseValidation:
        return 'There was an issue validating your purchase. Please contact support if this persists.';
      case RetryOperationType.imageGeneration:
        return 'Image generation failed. Please check your prompt and try again.';
      case RetryOperationType.imageEnhancement:
        return 'Image enhancement failed. Please try with a different image.';
      case RetryOperationType.profileUpdate:
        return 'Unable to update your profile. Please try again later.';
      case RetryOperationType.networkRequest:
        return 'Network request failed. Please check your connection and try again.';
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
    return '${duration.inSeconds}s';
  }
}

/// Mixin to add standardized retry functionality to StatefulWidgets
mixin StandardizedRetryMixin<T extends StatefulWidget> on State<T> {
  final RetryService _retryService = RetryService();
  
  /// Execute an operation with standardized retry logic and UI feedback
  Future<RetryResult<R>> executeWithRetry<R>({
    required Future<R> Function() operation,
    required RetryOperationType operationType,
    RetryConfig? config,
    String? operationName,
  }) async {
    return await _retryService.execute<R>(
      operation: operation,
      operationType: operationType,
      customConfig: config,
      operationName: operationName,
      onProgress: (attempt, maxAttempts, elapsed) {
        if (mounted) {
          // Subclasses can override this to update UI
          onRetryProgress(operationType, attempt, maxAttempts, elapsed);
        }
      },
    );
  }
  
  /// Override this method to handle retry progress updates
  void onRetryProgress(RetryOperationType operationType, int attempt, int maxAttempts, Duration elapsed) {
    // Default implementation does nothing
    // Subclasses can override to update loading states
  }
}
