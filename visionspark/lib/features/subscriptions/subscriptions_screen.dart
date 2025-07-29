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
import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:functions_client/functions_client.dart' as fn_client; // Not directly used anymore

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _purchaseStreamSubscription; // Renamed for clarity
  bool _iapLoading = true; // For IAP product loading
  bool _purchasePending = false;
  String? _iapError; // For IAP related errors
  String? _purchaseSuccessMessage;
  List<ProductDetails> _products = [];
  static const String monthlyUnlimitedId = 'monthly_unlimited_generations';

  // New state variables for active subscription status
  String? _activeSubscriptionType;
  int? _currentGenerationLimit;
  bool _isLoadingStatus = true; // For fetching active subscription status
  String? _statusErrorMessage;
  SubscriptionStatusNotifier? _subscriptionStatusNotifier;

  @override
  void initState() {
    super.initState();
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
      _fetchSubscriptionStatusWithRetry(); // Refetch status if notifier indicates a change
    });
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
              _currentGenerationLimit = data['limit'];
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

  Future<void> _fetchSubscriptionStatusWithRetry({int maxRetries = 3}) async {
    if (!mounted) return;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      print('🔄 Fetching subscription status (attempt $attempt/$maxRetries)...');

      await _fetchSubscriptionStatus();

      // If we got a subscription or this is the last attempt, stop retrying
      if (_activeSubscriptionType != null || attempt == maxRetries) {
        if (_activeSubscriptionType != null) {
          print('✅ Subscription status updated successfully: $_activeSubscriptionType');
        } else {
          print('⚠️ No active subscription found after $maxRetries attempts');
        }
        break;
      }

      // Wait before retrying (exponential backoff)
      if (attempt < maxRetries) {
        final delay = Duration(milliseconds: 1000 * attempt); // 1s, 2s, 3s
        print('⏳ Waiting ${delay.inMilliseconds}ms before retry...');
        await Future.delayed(delay);
      }
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
    const Set<String> ids = {monthlyUnlimitedId};
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
      // buyNonConsumable is the correct method for both non-consumable products AND subscriptions
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
          final valid = await _validateWithBackend(purchase);
          if (valid) {
            if (mounted) {
              setState(() {
                _purchaseSuccessMessage = 'Subscription activated successfully!';
                _iapError = null; // Clear IAP error on success
              });

              // Notify other parts of the app
              Provider.of<SubscriptionStatusNotifier>(context, listen: false).subscriptionChanged();

              // Also directly refresh the status with retry logic to ensure UI updates
              print('🔄 Purchase successful, refreshing subscription status...');
              _fetchSubscriptionStatusWithRetry();
            }
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
          } else {
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

      print('🚀 Calling validate-purchase-and-update-profile function...');
      final response = await Supabase.instance.client.functions.invoke(
        'validate-purchase-and-update-profile',
        body: requestBody,
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
    if (_isLoadingStatus) {
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
              final isActive = _activeSubscriptionType != null &&
                  (_activeSubscriptionType == 'monthly_unlimited_generations' && product.id == monthlyUnlimitedId);

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