// NOTE: You must add `in_app_purchase` to your pubspec.yaml dependencies for this screen to work:
// dependencies:
//   in_app_purchase: ^3.1.11

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _loading = true;
  bool _purchasePending = false;
  String? _error;
  String? _success;
  List<ProductDetails> _products = [];
  static const String monthly30Id = 'monthly_30_generations';
  static const String monthlyUnlimitedId = 'monthly_unlimited_generations';

  @override
  void initState() {
    super.initState();
    _initialize();
    _subscription = _iap.purchaseStream.listen(_onPurchaseUpdate, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      setState(() {
        _purchasePending = false;
        _error = 'Purchase error: $error';
      });
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      setState(() {
        _loading = false;
        _error = 'In-app purchases are not available.';
      });
      return;
    }
    const Set<String> ids = {monthly30Id, monthlyUnlimitedId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(ids);
    if (response.error != null) {
      setState(() {
        _loading = false;
        _error = response.error!.message;
      });
      return;
    }
    setState(() {
      _products = response.productDetails;
      _loading = false;
    });
  }

  void _buy(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    setState(() {
      _purchasePending = true;
      _error = null;
      _success = null;
    });
    _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        setState(() {
          _purchasePending = true;
        });
      } else {
        setState(() {
          _purchasePending = false;
        });
        if (purchase.status == PurchaseStatus.error) {
          setState(() {
            _error = 'Purchase failed: \\${purchase.error?.message ?? 'Unknown error'}';
          });
        } else if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          // TODO: Validate purchase with backend
          final valid = await _validateWithBackend(purchase);
          if (valid) {
            setState(() {
              _success = 'Subscription activated!';
              _error = null;
            });
            // Complete the purchase
            if (purchase.pendingCompletePurchase) {
              await _iap.completePurchase(purchase);
            }
          } else {
            setState(() {
              _error = 'Purchase validation failed. Please contact support.';
            });
          }
        }
      }
    }
  }

  Future<bool> _validateWithBackend(PurchaseDetails purchase) async {
    // TODO: Replace this with your actual backend endpoint and logic
    // Example: Call a Supabase Edge Function to validate the purchase
    // This is a placeholder and always returns true for demo purposes
    // You should send purchase.verificationData.serverVerificationData to your backend
    try {
      // final response = await http.post(
      //   Uri.parse('https://your-backend/validate-purchase'),
      //   headers: {'Content-Type': 'application/json'},
      //   body: jsonEncode({
      //     'source': purchase.verificationData.source,
      //     'serverVerificationData': purchase.verificationData.serverVerificationData,
      //     'productID': purchase.productID,
      //   }),
      // );
      // return response.statusCode == 200;
      await Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: colorScheme.error)));
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Choose your subscription',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        if (_success != null)
          Card(
            color: colorScheme.primary.withOpacity(0.1),
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_success!, style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),
          ),
        ..._products.map((product) => _SubscriptionCard(
              product: product,
              onPressed: _purchasePending ? null : () => _buy(product),
              isLoading: _purchasePending,
            )),
        if (_products.isEmpty)
          Card(
            color: colorScheme.surface,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: const [
                  Text('No subscriptions available.',
                      style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text('Please try again later.'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 32),
        Text(
          'Payments are securely processed by Google Play. You can cancel anytime in your Google Play account.',
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7), fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _SubscriptionCard extends StatelessWidget {
  final ProductDetails product;
  final VoidCallback? onPressed;
  final bool isLoading;
  const _SubscriptionCard({required this.product, this.onPressed, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      color: colorScheme.surface,
      margin: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(product.description,
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(product.price,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Subscribe', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} 