// NOTE: You must add `in_app_purchase` to your pubspec.yaml dependencies for this screen to work:
// dependencies:
//   in_app_purchase: ^3.1.11

import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'dart:convert';
// import 'package:http/http.dart' as http; // Not directly used anymore for validation
import 'package:provider/provider.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import '../../shared/design_system/design_system.dart';
import '../../shared/widgets/subscription_processing_widget.dart';
import '../../shared/services/subscription_processing_service.dart';
import '../../shared/services/retry_service.dart';
import '../../shared/widgets/standardized_loading_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:functions_client/functions_client.dart' as fn_client; // Not directly used anymore

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> with StandardizedRetryMixin {
  final InAppPurchase _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _purchaseStreamSubscription; // Renamed for clarity
  bool _iapLoading = true; // For IAP product loading
  bool _purchasePending = false;
  String? _iapError; // For IAP related errors
  String? _purchaseSuccessMessage;
  List<ProductDetails> _products = [];
  static const String monthlyUnlimitedId = 'monthly_unlimited_generations';
  static const String legacyMonthlyUnlimitedId = 'monthly_unlimited';

  // New state variables for active subscription status
  String? _activeSubscriptionType;
  int? _currentGenerationLimit;
  bool _isLoadingStatus = true; // For fetching active subscription status
  String? _statusErrorMessage;
  SubscriptionStatusNotifier? _subscriptionStatusNotifier;

  // Enhanced UI feedback state variables
  bool _isRetryingSubscriptionStatus = false;
  int _currentRetryAttempt = 0;
  int _maxRetryAttempts = 0;
  String? _retryStatusMessage;

  // Subscription processing service
  late SubscriptionProcessingService _processingService;

  @override
  void initState() {
    super.initState();
    _processingService = SubscriptionProcessingService();
    _initializeIap();
    _fetchSubscriptionStatus(); // Fetch current status on init
    _purchaseStreamSubscription = _iap.purchaseStream.listen(_onPurchaseUpdate, onDone: () {
      _purchaseStreamSubscription.cancel();
    }, onError: (error) {
      if (mounted) {
        setState(() {
          _purchasePending = false;
          _iapError = 'Purchase stream error: $error';
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = Provider.of<SubscriptionStatusNotifier>(context, listen: false);
    if (_subscriptionStatusNotifier != notifier) {
      _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
      _subscriptionStatusNotifier = notifier;
      _subscriptionStatusNotifier?.addListener(_onSubscriptionChanged);
    }
  }

  void _onSubscriptionChanged() {
    // Add a small delay to ensure database changes are propagated
    Future.delayed(const Duration(milliseconds: 500), () {
      _fetchSubscriptionStatusWithRetry(
        maxRetries: 5, // Moderate retry for general subscription changes
        maxTotalWait: const Duration(minutes: 1),
      );
    });
  }

  /// Intelligent polling mechanism for post-purchase subscription verification
  /// This method provides more aggressive polling specifically for purchase scenarios
  Future<void> _pollForSubscriptionAfterPurchase(String productId) async {
    if (!mounted) return;

    print('🔄 Starting intelligent polling for subscription after purchase: $productId');

    // Add initial delay to allow database propagation after purchase validation
    print('⏳ Waiting for database propagation before verification...');
    await Future.delayed(const Duration(seconds: 2));

    // First, try the enhanced retry mechanism
    await _fetchSubscriptionStatusWithRetry(
      maxRetries: 12, // More aggressive for purchases
      expectedProductId: productId,
      maxTotalWait: const Duration(minutes: 4), // Allow more time for purchase processing
    );

    // If still no subscription, start continuous polling with longer intervals
    if (_activeSubscriptionType == null && mounted) {
      print('🔄 Starting extended polling phase...');

      for (int i = 0; i < 6; i++) { // 6 more attempts over 3 minutes
        if (!mounted) break;

        await Future.delayed(const Duration(seconds: 30)); // 30-second intervals

        print('🔄 Extended polling attempt ${i + 1}/6...');
        await _fetchSubscriptionStatus();

        // Check if we found the expected subscription
        final expectedTier = productId == monthlyUnlimitedId ? 'monthly_unlimited_generations' :
                            productId == legacyMonthlyUnlimitedId ? 'monthly_unlimited' : null;

        if (_activeSubscriptionType != null &&
            (expectedTier == null || _activeSubscriptionType == expectedTier)) {
          print('✅ Extended polling successful: Found $_activeSubscriptionType');
          break;
        }
      }

      if (_activeSubscriptionType == null && mounted) {
        print('⚠️ Extended polling completed without finding subscription. This may indicate a backend issue.');
        // Could show a user-friendly message here about contacting support
      }
    }
  }

  Future<void> _fetchSubscriptionStatus() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStatus = true;
      _statusErrorMessage = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke('get-generation-status');
      if (mounted) {
        if (response.data != null) {
          final data = response.data;
          if (data['error'] != null) {
            setState(() {
              _statusErrorMessage = data['error'].toString();
              _activeSubscriptionType = null;
              _currentGenerationLimit = null;
            });
          } else {
            setState(() {
              _activeSubscriptionType = data['active_subscription_type'];
              _currentGenerationLimit = data['generation_limit'] ?? data['limit'];
              // If there's an active subscription, we might want to clear _purchaseSuccessMessage
              if (_activeSubscriptionType != null) {
                _purchaseSuccessMessage = null;
              }
            });

            // Update the global notifier with the new subscription status
            if (_subscriptionStatusNotifier != null) {
              _subscriptionStatusNotifier!.updateSubscriptionStatus(_activeSubscriptionType);
            }
          }
        } else {
          setState(() {
            _statusErrorMessage = 'Failed to fetch subscription status: No data received.';
            _activeSubscriptionType = null;
            _currentGenerationLimit = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusErrorMessage = 'Error fetching subscription status: ${e.toString()}';
          _activeSubscriptionType = null;
          _currentGenerationLimit = null;
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoadingStatus = false;
      });
    }
  }

  /// Enhanced retry mechanism using standardized retry service
  Future<void> _fetchSubscriptionStatusWithRetry({
    int maxRetries = 8,
    String? expectedProductId,
    Duration maxTotalWait = const Duration(minutes: 2),
  }) async {
    if (!mounted) return;

    // Update UI state to show retry progress
    if (mounted) {
      setState(() {
        _isRetryingSubscriptionStatus = true;
        _maxRetryAttempts = maxRetries;
        _currentRetryAttempt = 0;
        _retryStatusMessage = expectedProductId != null
          ? 'Verifying your subscription...'
          : 'Checking subscription status...';
      });
    }

    // Use standardized retry service with custom parameters for subscription verification
    final config = RetryConfig(
      maxRetries: maxRetries,
      maxTotalWait: maxTotalWait,
      baseDelay: const Duration(seconds: 2), // Slightly longer delay for database consistency
      backoffMultiplier: 1.5, // Less aggressive backoff for subscription checks
      maxDelay: const Duration(seconds: 15),
      useJitter: true,
    );

    final result = await executeWithRetry<bool>(
      operation: () async {
        await _fetchSubscriptionStatus();

        // Enhanced success detection
        if (_activeSubscriptionType != null) {
          if (expectedProductId != null) {
            // If we're looking for a specific product, verify it matches
            final expectedTier = expectedProductId == monthlyUnlimitedId ? 'monthly_unlimited_generations' :
                                expectedProductId == legacyMonthlyUnlimitedId ? 'monthly_unlimited' : null;

            if (expectedTier != null && _activeSubscriptionType == expectedTier) {
              print('✅ Found expected subscription: $_activeSubscriptionType');
              return true; // Success - found expected subscription
            } else {
              throw Exception('Expected subscription $expectedTier but found $_activeSubscriptionType');
            }
          } else {
            print('✅ Found active subscription: $_activeSubscriptionType');
            return true; // Success - any subscription is good
          }
        }

        // Provide more detailed error information for debugging
        // Use "temporary" keyword to ensure retry logic recognizes this as retryable
        final errorDetails = _statusErrorMessage != null
          ? (_statusErrorMessage!.toLowerCase().contains('temporary') ||
             _statusErrorMessage!.toLowerCase().contains('timeout') ||
             _statusErrorMessage!.toLowerCase().contains('connection')
             ? _statusErrorMessage!
             : 'Temporary API error: $_statusErrorMessage')
          : 'No active subscription found - temporary database propagation delay';
        print('🔍 Subscription verification failed: $errorDetails');
        throw Exception(errorDetails);
      },
      operationType: RetryOperationType.subscriptionStatus,
      config: config,
      operationName: expectedProductId != null
        ? 'Subscription Verification for $expectedProductId'
        : 'Subscription Status Check',
    );

    // Handle result
    if (mounted) {
      setState(() {
        _isRetryingSubscriptionStatus = false;
        _currentRetryAttempt = 0;
        _maxRetryAttempts = 0;
        _retryStatusMessage = null;
      });
    }

    if (!result.success) {
      if (expectedProductId != null) {
        print('⚠️ Expected subscription $expectedProductId not found after ${result.attempts} attempts');
      } else {
        print('⚠️ No active subscription found after ${result.attempts} attempts');
      }
    }
  }

  @override
  void onRetryProgress(RetryOperationType operationType, int attempt, int maxAttempts, Duration elapsed) {
    if (operationType == RetryOperationType.subscriptionStatus && mounted) {
      setState(() {
        _currentRetryAttempt = attempt;
        _maxRetryAttempts = maxAttempts;
        _retryStatusMessage = _currentRetryAttempt > 1
          ? 'Checking subscription status... (attempt $attempt/$maxAttempts)'
          : 'Checking subscription status...';
      });
    }
  }

  Future<void> _initializeIap() async {
    final bool available = await _iap.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _iapLoading = false;
        _iapError = 'In-app purchases are not available.';
      });
      return;
    }
    const Set<String> ids = {monthlyUnlimitedId, legacyMonthlyUnlimitedId};
    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(ids);
      if (!mounted) return;
      if (response.error != null) {
        setState(() {
          _iapLoading = false;
          _iapError = response.error!.message;
        });
        return;
      }
      setState(() {
        _products = response.productDetails;
        _iapLoading = false;
      });
    } catch (e) {
        if (mounted) {
            setState(() {
                _iapLoading = false;
                _iapError = "Error querying products: ${e.toString()}";
            });
        }
    }
  }

  void _buy(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    if (mounted) {
      setState(() {
        _purchasePending = true;
        _iapError = null; // Clear previous IAP error
        _purchaseSuccessMessage = null; // Clear previous success message
      });
    }
    try {
      // For subscriptions, use buyNonConsumable (this handles both non-consumables and subscriptions)
      // The in_app_purchase plugin automatically detects the product type
      print('🛒 Initiating purchase for product: ${product.id} (${product.title})');
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      if (mounted) {
        setState(() {
          _purchasePending = false;
          _iapError = "Error initiating purchase: ${e.toString()}";
        });
      }
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasePending = true);
      } else {
        if (mounted) setState(() => _purchasePending = false);
        if (purchase.status == PurchaseStatus.error) {
          if (mounted) {
            setState(() {
              _iapError = 'Purchase failed: ${purchase.error?.message ?? 'Unknown error'}';
            });
          }
        } else if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          // Start processing service
          _processingService.startProcessing(
            productId: purchase.productID,
            purchaseToken: purchase.verificationData.serverVerificationData,
            additionalDetails: {
              'Purchase Status': purchase.status.toString(),
              'Source': purchase.verificationData.source,
            },
          );

          final valid = await _validateWithBackend(purchase);
          if (valid) {
            if (mounted) {
              setState(() {
                _purchaseSuccessMessage = 'Subscription activated successfully!';
                _iapError = null; // Clear IAP error on success
              });

              // Complete processing service
              _processingService.completeProcessing(
                subscriptionDetails: {
                  'Product': purchase.productID,
                  'Status': 'Active',
                },
                successMessage: 'Your subscription is now active and ready to use!',
              );

              // Notify other parts of the app
              Provider.of<SubscriptionStatusNotifier>(context, listen: false).subscriptionChanged();

              // Use intelligent polling for post-purchase subscription verification
              print('🔄 Purchase successful, starting intelligent polling for subscription verification...');
              _pollForSubscriptionAfterPurchase(purchase.productID);
            }
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
          } else {
            // Handle processing error
            _processingService.handleError(
              errorMessage: _iapError ?? 'Purchase validation failed. Please contact support.',
              errorCode: 'VALIDATION_FAILED',
              isRetryable: true,
            );

            // _iapError would have been set by _validateWithBackend if validation failed there
            if (mounted && _iapError == null) { // Ensure an error message is shown
                 setState(() {
                    _iapError = 'Purchase validation failed. Please contact support.';
                });
            }
          }
        } else if (purchase.status == PurchaseStatus.canceled) {
            if (mounted) {
                setState(() {
                    _iapError = 'Purchase was cancelled.';
                });
            }
        }
      }
    }
  }

  Future<bool> _validateWithBackend(PurchaseDetails purchase) async {
    if (mounted) { // Clear previous specific error before new validation attempt
        setState(() {  _iapError = null; });
    }

    // Enhanced logging for debugging
    print('🔍 Starting purchase validation...');
    print('📦 Product ID: ${purchase.productID}');
    print('🎫 Purchase Token: ${purchase.verificationData.serverVerificationData.substring(0, 20)}...');
    print('📱 Source: ${purchase.verificationData.source}');
    print('✅ Purchase Status: ${purchase.status}');

    try {
      final requestBody = {
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'source': purchase.verificationData.source, // Include source for debugging
      };

      // Update processing phase to acknowledging
      _processingService.updatePhase(
        SubscriptionProcessingPhase.acknowledging,
        message: 'Validating and acknowledging your purchase...',
      );

      print('🚀 Calling validate-purchase-and-update-profile function...');
      final response = await Supabase.instance.client.functions.invoke(
        'validate-purchase-and-update-profile',
        body: requestBody,
      );

      // Update processing phase to updating profile
      _processingService.updatePhase(
        SubscriptionProcessingPhase.updatingProfile,
        message: 'Activating your subscription benefits...',
      );

      print('📡 Response Status: ${response.status}');
      print('📄 Response Data: ${jsonEncode(response.data)}');

      if (!mounted) return false;

      if (response.status == 200) {
        if (response.data != null && response.data['success'] == true) {
          print('✅ Purchase validation successful!');
          return true;
        } else {
          String errorMessage = 'Purchase validation failed on backend.';
          if (response.data != null && response.data['error'] != null) {
            errorMessage = response.data['error'].toString();
          } else {
            // Add a more descriptive message if backend returns non-200 but no explicit error in data
            errorMessage = 'Backend validation function returned success=false. Status: ${response.status}.';
            if (response.data != null) {
               errorMessage += ' Response: ${jsonEncode(response.data)}';
            }
          }
          print('❌ Validation failed: $errorMessage');
          setState(() => _iapError = errorMessage);
          return false;
        }
      } else {
        String errorMessage = 'Backend validation function returned error status: ${response.status}.';
        if (response.data != null && response.data is Map && response.data['error'] != null) {
          errorMessage += ' Details: ${response.data['error'].toString()}';
        } else if (response.data != null) {
          errorMessage += ' Response: ${jsonEncode(response.data)}';
        }
        print('❌ HTTP Error: $errorMessage');
        setState(() => _iapError = errorMessage);
        return false;
      }
    }
    catch (e) {
      if (!mounted) return false;
      String displayMessage = 'Error calling validation function: ${e.toString()}';
      if (e.toString().toLowerCase().contains('functionshttperror')) {
         try {
            final parts = e.toString().split(':');
            if (parts.length > 1) displayMessage = 'Validation Error: ${parts.sublist(1).join(':').trim()}';
         } catch (_) {/* Use original displayMessage */}
      }
      print('💥 Exception during validation: $displayMessage');
      setState(() => _iapError = displayMessage);
      return false;
    }
  }
  
  String _formatSubscriptionType(String? type) {
    if (type == monthlyUnlimitedId || type == 'monthly_unlimited') return 'Monthly Unlimited Generations'; // Handle raw tier ID
    if (type != null && type.isNotEmpty) { // Fallback for any other non-empty type
      return type.replaceAll('_', ' ').split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() + e.substring(1) : '').join(' ');
    }
    return 'N/A'; // Default if type is null or empty
  }

  /// Show support dialog with pre-filled transaction details
  void _showSupportDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          'Contact Support',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightBold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'re here to help! Please contact our support team with the following information:',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: VSDesignTokens.space3),
            if (_processingService.transactionDetails != null) ...[
              Container(
                padding: const EdgeInsets.all(VSDesignTokens.space3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transaction Details:',
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: VSTypography.weightBold,
                      ),
                    ),
                    const SizedBox(height: VSDesignTokens.space2),
                    ..._processingService.transactionDetails!.entries.map((entry) =>
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ).toList(),
                  ],
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
            ],
            Text(
              'Email: support@visionspark.app',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: colorScheme.primary),
            ),
          ),
          VSButton(
            text: 'Copy Details',
            onPressed: () {
              // TODO: Implement clipboard copy functionality
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Transaction details copied to clipboard'),
                  backgroundColor: colorScheme.primary,
                ),
              );
            },
            variant: VSButtonVariant.primary,
            size: VSButtonSize.small,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: VSResponsive.getResponsivePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildStatusSection(context, textTheme, colorScheme),
                const VSResponsiveSpacing(),
                _buildSubscriptionPlans(context, textTheme, colorScheme),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    return Column(
      children: [
        Icon(
          Icons.workspace_premium,
          size: VSDesignTokens.iconXXL,
          color: colorScheme.primary,
        ),
        const SizedBox(height: VSDesignTokens.space4),
        VSResponsiveText(
          text: 'VisionSpark Premium',
          baseStyle: textTheme.headlineMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: VSTypography.weightBold,
          ),
        ),
        const SizedBox(height: VSDesignTokens.space2),
        VSResponsiveText(
          text: 'Unlock unlimited creativity with premium features',
          baseStyle: textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatusSection(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    // Show subscription processing widget if processing
    return ListenableBuilder(
      listenable: _processingService,
      builder: (context, child) {
        if (_processingService.isProcessing || _processingService.hasError) {
          if (_processingService.hasError) {
            return VSCard(
              color: colorScheme.errorContainer.withValues(alpha: 0.3),
              elevation: VSDesignTokens.elevation2,
              padding: const EdgeInsets.all(VSDesignTokens.space4),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: colorScheme.error,
                  ),
                  const SizedBox(height: VSDesignTokens.space3),
                  Text(
                    'Processing Error',
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: VSTypography.weightBold,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    _processingService.errorMessage ?? 'An error occurred during processing',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VSDesignTokens.space3),
                  VSButton(
                    text: 'Contact Support',
                    onPressed: () => _showSupportDialog(context),
                    variant: VSButtonVariant.outline,
                    size: VSButtonSize.medium,
                    icon: const Icon(Icons.support_agent),
                  ),
                ],
              ),
            );
          }

          if (_processingService.currentPhase == SubscriptionProcessingPhase.completed) {
            return SubscriptionCompletionWidget(
              title: 'Subscription Activated!',
              message: _processingService.additionalMessage ?? 'Your subscription is now active and ready to use!',
              subscriptionDetails: _processingService.transactionDetails,
              onContinue: () {
                _processingService.reset();
                _fetchSubscriptionStatus();
              },
            );
          }

          return SubscriptionProcessingWidget(
            currentPhase: _processingService.currentPhase,
            estimatedTimeRemaining: _processingService.estimatedTimeRemaining,
            additionalMessage: _processingService.additionalMessage,
            showContactSupport: _processingService.currentPhase == SubscriptionProcessingPhase.validating,
            transactionDetails: _processingService.transactionDetails,
            onContactSupport: () => _showSupportDialog(context),
          );
        }

        // Show enhanced retry progress if retrying
        if (_isRetryingSubscriptionStatus) {
          return VSCard(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            elevation: VSDesignTokens.elevation1,
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Column(
              children: [
                VSLoadingIndicator(
                  message: _retryStatusMessage ?? 'Verifying subscription...',
                  size: VSDesignTokens.iconL,
                ),
                if (_maxRetryAttempts > 0) ...[
                  const SizedBox(height: VSDesignTokens.space3),
                  LinearProgressIndicator(
                    value: _currentRetryAttempt / _maxRetryAttempts,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    'Attempt $_currentRetryAttempt of $_maxRetryAttempts',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          );
        } else if (_isLoadingStatus) {
          return Center(
            child: VSLoadingIndicator(
              message: 'Loading subscription status...',
              size: VSDesignTokens.iconL,
            ),
          );
        } else if (_statusErrorMessage != null) {
          return VSCard(
            color: colorScheme.errorContainer.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Text(
              _statusErrorMessage!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
          );
        } else if (_activeSubscriptionType != null) {
          return VSCard(
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            elevation: VSDesignTokens.elevation2,
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconL,
                ),
                const SizedBox(height: VSDesignTokens.space3),
                Text(
                  'Your Active Subscription',
                  style: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
                const SizedBox(height: VSDesignTokens.space2),
                Text(
                  _formatSubscriptionType(_activeSubscriptionType),
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: VSTypography.weightBold,
                  ),
                ),
                if (_currentGenerationLimit != null) ...[
                  const SizedBox(height: VSDesignTokens.space1),
                  Text(
                    'Generation Limit: ${_currentGenerationLimit == -1 ? "Unlimited" : _currentGenerationLimit}',
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          );
        } else {
          return VSCard(
            color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            child: Column(
              children: [
                Icon(
                  Icons.info_outline,
                  color: colorScheme.onSecondaryContainer,
                  size: VSDesignTokens.iconL,
                ),
                const SizedBox(height: VSDesignTokens.space3),
                Text(
                  'No active subscription found',
                  style: textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: VSTypography.weightMedium,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: VSDesignTokens.space2),
                Text(
                  'Choose a plan below to unlock premium features',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSubscriptionPlans(BuildContext context, TextTheme textTheme, ColorScheme colorScheme) {
    if (_iapLoading) {
      return Center(
        child: VSLoadingIndicator(
          message: 'Loading subscription plans...',
          size: VSDesignTokens.iconL,
        ),
      );
    } else if (_iapError != null && _products.isEmpty) {
      return VSCard(
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        padding: const EdgeInsets.all(VSDesignTokens.space4),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              color: colorScheme.onErrorContainer,
              size: VSDesignTokens.iconL,
            ),
            const SizedBox(height: VSDesignTokens.space3),
            Text(
              'Unable to load subscription plans',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onErrorContainer,
                fontWeight: VSTypography.weightMedium,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              _iapError!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VSResponsiveText(
            text: 'Available Plans',
            baseStyle: textTheme.titleLarge?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space4),

          if (_purchaseSuccessMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: VSDesignTokens.space4),
              child: VSCard(
                color: colorScheme.primaryContainer.withValues(alpha: 0.2),
                padding: const EdgeInsets.all(VSDesignTokens.space4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: colorScheme.primary,
                      size: VSDesignTokens.iconM,
                    ),
                    const SizedBox(width: VSDesignTokens.space3),
                    Expanded(
                      child: Text(
                        _purchaseSuccessMessage!,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_products.isEmpty)
            VSEmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'No subscription plans available',
              subtitle: 'Please try again later or contact support',
            )
          else
            ...(_products.map((product) {
              final isActive =
                  (_activeSubscriptionType == 'monthly_unlimited_generations' && product.id == monthlyUnlimitedId) ||
                  (_activeSubscriptionType == 'monthly_unlimited' && product.id == legacyMonthlyUnlimitedId);

              return Padding(
                padding: const EdgeInsets.only(bottom: VSDesignTokens.space4),
                child: _SubscriptionCard(
                  product: product,
                  onPressed: isActive || _purchasePending ? null : () => _buy(product),
                  isLoading: _purchasePending,
                  isActive: isActive,
                ),
              );
            }).toList()),
        ],
      );
    }
  }

  @override
  void dispose() {
    _purchaseStreamSubscription.cancel();
    _subscriptionStatusNotifier?.removeListener(_onSubscriptionChanged);
    super.dispose();
  }
}

class _SubscriptionCard extends StatelessWidget {
  final ProductDetails product;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isActive;

  const _SubscriptionCard({
    required this.product,
    this.onPressed,
    this.isLoading = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSCard(
      color: isActive
        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
        : colorScheme.surfaceContainerHighest,
      elevation: isActive ? VSDesignTokens.elevation4 : VSDesignTokens.elevation2,
      borderRadius: VSDesignTokens.radiusL,
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isActive) ...[
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                  size: VSDesignTokens.iconM,
                ),
                const SizedBox(width: VSDesignTokens.space2),
              ],
              Expanded(
                child: Text(
                  product.title,
                  style: textTheme.titleLarge?.copyWith(
                    color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Text(
            product.description,
            style: textTheme.bodyMedium?.copyWith(
              color: isActive
                ? colorScheme.onPrimaryContainer.withValues(alpha: 0.8)
                : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Price',
                    style: textTheme.labelMedium?.copyWith(
                      color: isActive
                        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    product.price,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: VSTypography.weightBold,
                      color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              VSButton(
                text: isActive ? 'Active' : 'Subscribe',
                onPressed: onPressed,
                isLoading: isLoading,
                variant: isActive ? VSButtonVariant.outline : VSButtonVariant.primary,
                size: VSButtonSize.medium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}