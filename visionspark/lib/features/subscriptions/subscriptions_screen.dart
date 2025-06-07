// NOTE: You must add `in_app_purchase` to your pubspec.yaml dependencies for this screen to work:
// dependencies:
//   in_app_purchase: ^3.1.11

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'dart:convert';
// import 'package:http/http.dart' as http; // Not directly used anymore for validation
import 'package:provider/provider.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
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
  static const String monthly30Id = 'monthly_30';
  static const String monthlyUnlimitedId = 'monthly_unlimited';

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
    _fetchSubscriptionStatus(); // Refetch status if notifier indicates a change
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
    const Set<String> ids = {monthly30Id, monthlyUnlimitedId};
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
              // Notify other parts of the app and fetch updated status
              Provider.of<SubscriptionStatusNotifier>(context, listen: false).subscriptionChanged();
              // _fetchSubscriptionStatus(); // Already handled by the notifier listener
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
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'validate-purchase-and-update-profile',
        body: {
          'productId': purchase.productID,
          'purchaseToken': purchase.verificationData.serverVerificationData,
          // 'source': purchase.verificationData.source, // Optional: send if your backend uses it
        },
      );

      if (!mounted) return false;

      if (response.status == 200) {
        if (response.data != null && response.data['success'] == true) {
          return true;
        } else {
          String errorMessage = 'Purchase validation failed on backend.';
          if (response.data != null && response.data['error'] != null) {
            errorMessage = response.data['error'].toString();
          }
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
      setState(() => _iapError = displayMessage);
      return false;
    }
  }
  
  String _formatSubscriptionType(String? type) {
    if (type == monthly30Id || type == 'monthly_30') return 'Monthly 30 Generations'; // Handle raw tier ID
    if (type == monthlyUnlimitedId || type == 'monthly_unlimited') return 'Monthly Unlimited Generations'; // Handle raw tier ID
    if (type != null && type.isNotEmpty) { // Fallback for any other non-empty type
      return type.replaceAll('_', ' ').split(' ').map((e) => e.isNotEmpty ? e[0].toUpperCase() + e.substring(1) : '').join(' ');
    }
    return 'N/A'; // Default if type is null or empty
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget statusSection;
    if (_isLoadingStatus) {
      statusSection = const Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0),
          child: Center(child: CircularProgressIndicator()));
    } else if (_statusErrorMessage != null) {
      statusSection = Padding(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          color: colorScheme.errorContainer.withOpacity(0.5),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_statusErrorMessage!, style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 16), textAlign: TextAlign.center),
          )
        ),
      );
    } else if (_activeSubscriptionType != null) {
      statusSection = Card(
        color: colorScheme.primaryContainer.withOpacity(0.3),
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Your Active Subscription', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: colorScheme.onPrimaryContainer)),
              const SizedBox(height: 8),
              Text(_formatSubscriptionType(_activeSubscriptionType), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if(_currentGenerationLimit != null)
                 Text('Generation Limit: ${_currentGenerationLimit == -1 ? "Unlimited" : _currentGenerationLimit}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.onPrimaryContainer)),
            ],
          ),
        ),
      );
    } else {
       statusSection = Card(
        color: colorScheme.secondaryContainer.withOpacity(0.3),
        margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('No active subscription found.', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.onSecondaryContainer), textAlign: TextAlign.center),
        ),
      );
    }


    return Scaffold( // Added Scaffold
      // appBar: AppBar(title: Text('Manage Subscriptions')), // Optional: Add AppBar
      body: ListView(
        padding: const EdgeInsets.all(16), // Adjusted padding
        children: [
          Text('Manage Your Subscription', // Changed title
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), // Adjusted style
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          
          statusSection, // Display current subscription status

          if (_iapLoading) const Center(child: CircularProgressIndicator())
          else if (_iapError != null && _products.isEmpty) // Show IAP error only if no products loaded
             Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  color: colorScheme.errorContainer.withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_iapError!, style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 16), textAlign: TextAlign.center),
                  )
                ),
              )
          else ...[ // Display products if available or a message if not
            const SizedBox(height: 16),
            Text('Available Plans',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),

            if (_purchaseSuccessMessage != null) // Display purchase success message here
              Padding(
                padding: const EdgeInsets.symmetric(vertical:8.0),
                child: Card(
                  color: Colors.green.withOpacity(0.15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_purchaseSuccessMessage!, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                      ],
                    ),
                  ),
                ),
              ),
            
            // Display IAP specific error here, if purchase success is not shown.
            if (_purchaseSuccessMessage == null && _iapError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical:8.0),
                child: Card(
                  color: colorScheme.errorContainer.withOpacity(0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_iapError!, style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 16), textAlign: TextAlign.center),
                  )
                ),
              ),

            if (_products.isNotEmpty)
              ..._products.map((product) => _SubscriptionCard(
                    product: product,
                    onPressed: _purchasePending || (_activeSubscriptionType == product.id) ? null : () => _buy(product),
                    isLoading: _purchasePending,
                    isActive: _activeSubscriptionType == product.id,
                  ))
            else if (!_iapLoading) // Only show "No subscriptions" if not loading and no IAP error blocking products.
              Card(
                color: colorScheme.surfaceVariant,
                margin: const EdgeInsets.symmetric(vertical: 12),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: const [
                      Text('No subscription plans available at the moment.',
                          style: TextStyle(fontSize: 18)),
                      SizedBox(height: 8),
                      Text('Please check back later.'),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Payments are securely processed by the play store. You can manage or cancel your subscription anytime through your play store account settings.',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ]
        ],
      ),
    );
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
  final bool isActive; // New parameter
  const _SubscriptionCard({required this.product, this.onPressed, this.isLoading = false, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: isActive ? colorScheme.primaryContainer.withOpacity(0.5) : colorScheme.surfaceContainerHighest, // Highlight if active
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: isActive ? 4 : 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text(product.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: isActive ? colorScheme.onPrimaryContainer.withOpacity(0.8) : colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(product.price,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: isActive ? colorScheme.onPrimaryContainer : colorScheme.onSurface)),
                ElevatedButton(
                  onPressed: onPressed, // Will be null if active or purchase pending
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isActive ? colorScheme.outlineVariant : colorScheme.primary,
                    foregroundColor: isActive ? colorScheme.onSurfaceVariant : colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isActive ? 'Active' : 'Subscribe', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 