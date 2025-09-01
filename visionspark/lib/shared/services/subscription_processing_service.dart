import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/subscription_processing_widget.dart';

/// Service for managing subscription processing state and phases
class SubscriptionProcessingService extends ChangeNotifier {
  static final SubscriptionProcessingService _instance = SubscriptionProcessingService._internal();
  factory SubscriptionProcessingService() => _instance;
  SubscriptionProcessingService._internal();

  SubscriptionProcessingPhase _currentPhase = SubscriptionProcessingPhase.validating;
  String? _estimatedTimeRemaining;
  String? _additionalMessage;
  String? _errorMessage;
  bool _isProcessing = false;
  bool _hasError = false;
  Map<String, dynamic>? _transactionDetails;
  Timer? _phaseTimer;
  Timer? _timeEstimateTimer;
  DateTime? _processingStartTime;

  // Getters
  SubscriptionProcessingPhase get currentPhase => _currentPhase;
  String? get estimatedTimeRemaining => _estimatedTimeRemaining;
  String? get additionalMessage => _additionalMessage;
  String? get errorMessage => _errorMessage;
  bool get isProcessing => _isProcessing;
  bool get hasError => _hasError;
  Map<String, dynamic>? get transactionDetails => _transactionDetails;

  /// Start the subscription processing flow
  void startProcessing({
    required String productId,
    required String purchaseToken,
    Map<String, dynamic>? additionalDetails,
  }) {
    _isProcessing = true;
    _hasError = false;
    _errorMessage = null;
    _processingStartTime = DateTime.now();
    _currentPhase = SubscriptionProcessingPhase.validating;
    _transactionDetails = {
      'Product ID': productId,
      'Started': DateTime.now().toString().substring(0, 19),
      ...?additionalDetails,
    };
    
    _updateEstimatedTime();
    _startPhaseTimer();
    notifyListeners();
  }

  /// Update the current processing phase
  void updatePhase(SubscriptionProcessingPhase phase, {String? message}) {
    if (_currentPhase == phase) return;
    
    _currentPhase = phase;
    _additionalMessage = message;
    _updateEstimatedTime();
    
    // Update transaction details with phase completion time
    if (_transactionDetails != null) {
      _transactionDetails![phase.title] = DateTime.now().toString().substring(0, 19);
    }
    
    notifyListeners();
  }

  /// Complete the processing successfully
  void completeProcessing({
    Map<String, dynamic>? subscriptionDetails,
    String? successMessage,
  }) {
    _currentPhase = SubscriptionProcessingPhase.completed;
    _isProcessing = false;
    _estimatedTimeRemaining = null;
    _additionalMessage = successMessage ?? 'Your subscription is now active!';
    
    if (_transactionDetails != null && subscriptionDetails != null) {
      _transactionDetails!.addAll(subscriptionDetails);
      _transactionDetails!['Completed'] = DateTime.now().toString().substring(0, 19);
      
      // Calculate total processing time
      if (_processingStartTime != null) {
        final duration = DateTime.now().difference(_processingStartTime!);
        _transactionDetails!['Total Time'] = '${duration.inSeconds}s';
      }
    }
    
    _stopTimers();
    notifyListeners();
  }

  /// Handle processing error
  void handleError({
    required String errorMessage,
    String? errorCode,
    bool isRetryable = false,
    Map<String, dynamic>? errorContext,
  }) {
    _hasError = true;
    _errorMessage = errorMessage;
    _isProcessing = false;
    _estimatedTimeRemaining = null;
    
    if (_transactionDetails != null) {
      _transactionDetails!['Error'] = errorMessage;
      _transactionDetails!['Error Code'] = errorCode ?? 'Unknown';
      _transactionDetails!['Retryable'] = isRetryable.toString();
      _transactionDetails!['Error Time'] = DateTime.now().toString().substring(0, 19);
      
      if (errorContext != null) {
        _transactionDetails!.addAll(errorContext);
      }
    }
    
    _stopTimers();
    notifyListeners();
  }

  /// Reset the processing state
  void reset() {
    _currentPhase = SubscriptionProcessingPhase.validating;
    _estimatedTimeRemaining = null;
    _additionalMessage = null;
    _errorMessage = null;
    _isProcessing = false;
    _hasError = false;
    _transactionDetails = null;
    _processingStartTime = null;
    _stopTimers();
    notifyListeners();
  }

  /// Update estimated time remaining based on current phase
  void _updateEstimatedTime() {
    switch (_currentPhase) {
      case SubscriptionProcessingPhase.validating:
        _estimatedTimeRemaining = '30-60 seconds';
        break;
      case SubscriptionProcessingPhase.acknowledging:
        _estimatedTimeRemaining = '15-30 seconds';
        break;
      case SubscriptionProcessingPhase.updatingProfile:
        _estimatedTimeRemaining = '10-20 seconds';
        break;
      case SubscriptionProcessingPhase.completing:
        _estimatedTimeRemaining = '5-10 seconds';
        break;
      case SubscriptionProcessingPhase.completed:
        _estimatedTimeRemaining = null;
        break;
    }
  }

  /// Start timer for automatic phase progression (fallback)
  void _startPhaseTimer() {
    _phaseTimer?.cancel();
    
    // Set up fallback phase progression in case manual updates don't come
    int timeoutSeconds;
    switch (_currentPhase) {
      case SubscriptionProcessingPhase.validating:
        timeoutSeconds = 90; // 1.5 minutes
        break;
      case SubscriptionProcessingPhase.acknowledging:
        timeoutSeconds = 45; // 45 seconds
        break;
      case SubscriptionProcessingPhase.updatingProfile:
        timeoutSeconds = 30; // 30 seconds
        break;
      case SubscriptionProcessingPhase.completing:
        timeoutSeconds = 15; // 15 seconds
        break;
      case SubscriptionProcessingPhase.completed:
        return; // No timeout for completed state
    }
    
    _phaseTimer = Timer(Duration(seconds: timeoutSeconds), () {
      if (_isProcessing && !_hasError) {
        // If we're still processing and no error, something might be stuck
        handleError(
          errorMessage: 'Processing is taking longer than expected. Please try again or contact support.',
          errorCode: 'PROCESSING_TIMEOUT',
          isRetryable: true,
        );
      }
    });
    
    // Start time estimate countdown
    _startTimeEstimateTimer();
  }

  /// Start timer for updating time estimates
  void _startTimeEstimateTimer() {
    _timeEstimateTimer?.cancel();
    
    _timeEstimateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isProcessing || _hasError) {
        timer.cancel();
        return;
      }
      
      // Update time estimates to be more accurate as time passes
      if (_processingStartTime != null) {
        final elapsed = DateTime.now().difference(_processingStartTime!);
        
        switch (_currentPhase) {
          case SubscriptionProcessingPhase.validating:
            if (elapsed.inSeconds > 30) {
              _estimatedTimeRemaining = '30-45 seconds';
            }
            break;
          case SubscriptionProcessingPhase.acknowledging:
            if (elapsed.inSeconds > 60) {
              _estimatedTimeRemaining = '10-20 seconds';
            }
            break;
          case SubscriptionProcessingPhase.updatingProfile:
            if (elapsed.inSeconds > 90) {
              _estimatedTimeRemaining = '5-15 seconds';
            }
            break;
          case SubscriptionProcessingPhase.completing:
            _estimatedTimeRemaining = 'Almost done...';
            break;
          case SubscriptionProcessingPhase.completed:
            timer.cancel();
            return;
        }
        
        notifyListeners();
      }
    });
  }

  /// Stop all timers
  void _stopTimers() {
    _phaseTimer?.cancel();
    _timeEstimateTimer?.cancel();
    _phaseTimer = null;
    _timeEstimateTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}

/// Extension to provide user-friendly phase descriptions
extension SubscriptionProcessingPhaseExtension on SubscriptionProcessingPhase {
  String get userFriendlyDescription {
    switch (this) {
      case SubscriptionProcessingPhase.validating:
        return 'We\'re verifying your purchase with Google Play to ensure everything is legitimate and secure.';
      case SubscriptionProcessingPhase.acknowledging:
        return 'Confirming your purchase with Google Play to prevent any automatic refunds.';
      case SubscriptionProcessingPhase.updatingProfile:
        return 'Activating your subscription benefits and updating your account settings.';
      case SubscriptionProcessingPhase.completing:
        return 'Finalizing your subscription and preparing your enhanced features.';
      case SubscriptionProcessingPhase.completed:
        return 'Your subscription is now fully active and ready to use!';
    }
  }

  IconData get icon {
    switch (this) {
      case SubscriptionProcessingPhase.validating:
        return Icons.verified_user;
      case SubscriptionProcessingPhase.acknowledging:
        return Icons.handshake;
      case SubscriptionProcessingPhase.updatingProfile:
        return Icons.account_circle;
      case SubscriptionProcessingPhase.completing:
        return Icons.auto_awesome;
      case SubscriptionProcessingPhase.completed:
        return Icons.check_circle;
    }
  }
}
