import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/design_system/design_system.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import '../../shared/services/retry_service.dart';
import '../../shared/services/subscription_processing_service.dart';
import '../../shared/widgets/standardized_loading_widget.dart';
import '../../shared/widgets/subscription_processing_widget.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen>
    with StandardizedRetryMixin {
  static const String monthlyUnlimitedId = 'monthly_unlimited_generations';
  static const String legacyMonthlyUnlimitedId = 'monthly_unlimited';

  final _iap = InAppPurchase.instance;
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSub;
  final SubscriptionProcessingService _processing = SubscriptionProcessingService();

  bool _iapLoading = true;
  bool _purchasePending = false;
  String? _iapError;
  String? _purchaseSuccessMessage;
  List<ProductDetails> _products = [];

  String? _activeTier;
  int? _generationLimit;
  bool _statusLoading = true;
  String? _statusError;

  bool _retrying = false;
  int _retryAttempt = 0;
  int _retryMax = 0;
  String? _retryMessage;

  SubscriptionStatusNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    _initIap();
    _fetchStatus();
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _purchaseSub.cancel(),
      onError: (e) {
        if (mounted) {
          setState(() {
            _purchasePending = false;
            _iapError = 'Purchase stream error: $e';
          });
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = Provider.of<SubscriptionStatusNotifier>(context, listen: false);
    if (_notifier != n) {
      _notifier?.removeListener(_onSubscriptionChanged);
      _notifier = n;
      _notifier?.addListener(_onSubscriptionChanged);
    }
  }

  @override
  void dispose() {
    _purchaseSub.cancel();
    _notifier?.removeListener(_onSubscriptionChanged);
    super.dispose();
  }

  // ── IAP ─────────────────────────────────────────────────────────────────

  Future<void> _initIap() async {
    final available = await _iap.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _iapLoading = false;
        _iapError = 'In-app purchases are not available on this device.';
      });
      return;
    }
    try {
      final resp = await _iap.queryProductDetails({
        monthlyUnlimitedId,
        legacyMonthlyUnlimitedId,
      });
      if (!mounted) return;
      setState(() {
        _iapLoading = false;
        if (resp.error != null) {
          _iapError = resp.error!.message;
        } else {
          _products = resp.productDetails;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _iapLoading = false;
          _iapError = 'Could not load products: $e';
        });
      }
    }
  }

  void _buy(ProductDetails product) async {
    setState(() {
      _purchasePending = true;
      _iapError = null;
      _purchaseSuccessMessage = null;
    });
    try {
      await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      if (mounted) {
        setState(() {
          _purchasePending = false;
          _iapError = 'Could not start purchase: $e';
        });
      }
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        if (mounted) setState(() => _purchasePending = true);
        continue;
      }
      if (mounted) setState(() => _purchasePending = false);

      switch (p.status) {
        case PurchaseStatus.error:
          if (mounted) {
            setState(() =>
                _iapError = 'Purchase failed: ${p.error?.message ?? "Unknown error"}');
          }
          break;
        case PurchaseStatus.canceled:
          if (mounted) setState(() => _iapError = 'Purchase cancelled.');
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _processing.startProcessing(
            productId: p.productID,
            purchaseToken: p.verificationData.serverVerificationData,
            additionalDetails: {
              'Purchase Status': p.status.toString(),
              'Source': p.verificationData.source,
            },
          );
          final ok = await _validateWithBackend(p);
          if (ok) {
            if (mounted) {
              setState(() {
                _purchaseSuccessMessage = 'Subscription activated.';
                _iapError = null;
              });
              _processing.completeProcessing(
                subscriptionDetails: {
                  'Product': p.productID,
                  'Status': 'Active',
                },
                successMessage: 'Your subscription is now active!',
              );
              Provider.of<SubscriptionStatusNotifier>(context, listen: false)
                  .subscriptionChanged();
              _pollAfterPurchase(p.productID);
            }
            if (p.pendingCompletePurchase) await _iap.completePurchase(p);
          } else {
            _processing.handleError(
              errorMessage: _iapError ?? 'Purchase validation failed.',
              errorCode: 'VALIDATION_FAILED',
              isRetryable: true,
            );
            if (mounted && _iapError == null) {
              setState(() => _iapError = 'Purchase validation failed.');
            }
          }
          break;
        case PurchaseStatus.pending:
          break;
      }
    }
  }

  Future<bool> _validateWithBackend(PurchaseDetails p) async {
    if (mounted) setState(() => _iapError = null);
    try {
      _processing.updatePhase(
        SubscriptionProcessingPhase.acknowledging,
        message: 'Validating with Google Play…',
      );
      final resp = await Supabase.instance.client.functions.invoke(
        'validate-purchase-and-update-profile',
        body: {
          'productId': p.productID,
          'purchaseToken': p.verificationData.serverVerificationData,
          'source': p.verificationData.source,
        },
      );
      _processing.updatePhase(
        SubscriptionProcessingPhase.updatingProfile,
        message: 'Activating your benefits…',
      );
      if (!mounted) return false;
      if (resp.status == 200 && resp.data?['success'] == true) {
        return true;
      }
      final err = resp.data is Map && resp.data['error'] != null
          ? resp.data['error'].toString()
          : 'Backend returned ${resp.status}.';
      setState(() => _iapError = err);
      return false;
    } catch (e) {
      if (mounted) setState(() => _iapError = 'Validation error: $e');
      return false;
    }
  }

  Future<void> _pollAfterPurchase(String productId) async {
    if (!mounted) return;
    await Future.delayed(const Duration(seconds: 5));
    await _fetchStatusWithRetry(
      maxRetries: 12,
      expectedProductId: productId,
      maxTotalWait: const Duration(minutes: 4),
    );
    if (_activeTier == null && mounted) {
      for (var i = 0; i < 6; i++) {
        if (!mounted) break;
        await Future.delayed(const Duration(seconds: 30));
        await _fetchStatus();
        final expected = productId == monthlyUnlimitedId
            ? 'monthly_unlimited_generations'
            : productId == legacyMonthlyUnlimitedId
                ? 'monthly_unlimited'
                : null;
        if (_activeTier != null && (expected == null || _activeTier == expected)) {
          break;
        }
      }
    }
  }

  // ── Status fetching ────────────────────────────────────────────────────

  void _onSubscriptionChanged() {
    Future.delayed(const Duration(milliseconds: 500), () {
      _fetchStatusWithRetry(
        maxRetries: 5,
        maxTotalWait: const Duration(minutes: 1),
      );
    });
  }

  Future<void> _fetchStatus() async {
    if (!mounted) return;
    setState(() {
      _statusLoading = true;
      _statusError = null;
    });
    try {
      final resp = await Supabase.instance.client.functions
          .invoke('get-generation-status');
      if (!mounted) return;
      final data = resp.data;
      if (data == null) {
        setState(() => _statusError = 'No data received.');
      } else if (data['error'] != null) {
        setState(() {
          _statusError = data['error'].toString();
          _activeTier = null;
          _generationLimit = null;
        });
      } else {
        setState(() {
          _activeTier = data['active_subscription_type'] as String?;
          _generationLimit = (data['generation_limit'] ?? data['limit']) as int?;
          if (_activeTier != null) _purchaseSuccessMessage = null;
        });
        _notifier?.updateSubscriptionStatus(_activeTier);
      }
    } catch (e) {
      if (mounted) setState(() => _statusError = 'Could not fetch status: $e');
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  Future<void> _fetchStatusWithRetry({
    int maxRetries = 8,
    String? expectedProductId,
    Duration maxTotalWait = const Duration(minutes: 2),
  }) async {
    if (!mounted) return;
    setState(() {
      _retrying = true;
      _retryMax = maxRetries;
      _retryAttempt = 0;
      _retryMessage = expectedProductId != null
          ? 'Verifying your subscription…'
          : 'Checking subscription status…';
    });
    final config = RetryConfig(
      maxRetries: maxRetries,
      maxTotalWait: maxTotalWait,
      baseDelay: const Duration(seconds: 2),
      backoffMultiplier: 1.5,
      maxDelay: const Duration(seconds: 15),
      useJitter: true,
    );
    await executeWithRetry<bool>(
      operation: () async {
        await _fetchStatus();
        if (_activeTier != null) {
          if (expectedProductId != null) {
            final expected = expectedProductId == monthlyUnlimitedId
                ? 'monthly_unlimited_generations'
                : expectedProductId == legacyMonthlyUnlimitedId
                    ? 'monthly_unlimited'
                    : null;
            if (expected != null && _activeTier == expected) return true;
            throw Exception('Expected $expected, got $_activeTier — temporary');
          }
          return true;
        }
        throw Exception('No active subscription — temporary database delay');
      },
      operationType: RetryOperationType.subscriptionStatus,
      config: config,
      operationName: expectedProductId != null
          ? 'Subscription verification for $expectedProductId'
          : 'Subscription status check',
    );
    if (mounted) {
      setState(() {
        _retrying = false;
        _retryAttempt = 0;
        _retryMax = 0;
        _retryMessage = null;
      });
    }
  }

  @override
  void onRetryProgress(
    RetryOperationType operationType,
    int attempt,
    int maxAttempts,
    Duration elapsed,
  ) {
    if (operationType == RetryOperationType.subscriptionStatus && mounted) {
      setState(() {
        _retryAttempt = attempt;
        _retryMax = maxAttempts;
        _retryMessage = attempt > 1
            ? 'Checking subscription status… ($attempt/$maxAttempts)'
            : 'Checking subscription status…';
      });
    }
  }

  String _tierLabel(String? type) {
    if (type == null) return 'N/A';
    if (type == monthlyUnlimitedId || type == 'monthly_unlimited') {
      return 'Monthly Unlimited';
    }
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: ListView(
            padding: VSResponsive.getResponsivePadding(context),
            children: [
              _hero(),
              const SizedBox(height: VSDesignTokens.space5),
              _statusSection(),
              const SizedBox(height: VSDesignTokens.space5),
              _plans(),
              const SizedBox(height: VSDesignTokens.space12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXXL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.32),
            cs.secondary.withValues(alpha: 0.18),
          ],
        ),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.workspace_premium_rounded,
                color: cs.primary, size: VSDesignTokens.iconL),
          ),
          const SizedBox(height: VSDesignTokens.space4),
          Text(
            'VisionSpark Premium',
            style: tt.headlineMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightBold,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Text(
            'Unlock unlimited generations and faster iteration.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _statusSection() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: _processing,
      builder: (_, __) {
        if (_processing.isProcessing || _processing.hasError) {
          if (_processing.hasError) {
            return VSCard(
              padding: const EdgeInsets.all(VSDesignTokens.space5),
              borderRadius: VSDesignTokens.radiusXL,
              color: cs.errorContainer,
              child: Column(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: cs.onErrorContainer, size: VSDesignTokens.iconL),
                  const SizedBox(height: VSDesignTokens.space3),
                  Text(
                    'Processing error',
                    style: tt.titleLarge?.copyWith(
                      color: cs.onErrorContainer,
                      fontWeight: VSTypography.weightBold,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    _processing.errorMessage ?? 'Something went wrong.',
                    style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VSDesignTokens.space4),
                  VSButton(
                    text: 'Contact support',
                    icon: const Icon(Icons.support_agent),
                    variant: VSButtonVariant.outline,
                    onPressed: () => _showSupportDialog(),
                  ),
                ],
              ),
            );
          }
          if (_processing.currentPhase == SubscriptionProcessingPhase.completed) {
            return SubscriptionCompletionWidget(
              title: 'Subscription activated!',
              message: _processing.additionalMessage ??
                  'Your subscription is active.',
              subscriptionDetails: _processing.transactionDetails,
              onContinue: () {
                _processing.reset();
                _fetchStatus();
              },
            );
          }
          return SubscriptionProcessingWidget(
            currentPhase: _processing.currentPhase,
            estimatedTimeRemaining: _processing.estimatedTimeRemaining,
            additionalMessage: _processing.additionalMessage,
            showContactSupport:
                _processing.currentPhase == SubscriptionProcessingPhase.validating,
            transactionDetails: _processing.transactionDetails,
            onContactSupport: () => _showSupportDialog(),
          );
        }

        if (_retrying) {
          return VSCard(
            padding: const EdgeInsets.all(VSDesignTokens.space5),
            borderRadius: VSDesignTokens.radiusXL,
            color: cs.surfaceContainer,
            child: Column(
              children: [
                VSLoadingIndicator(message: _retryMessage ?? 'Verifying…'),
                if (_retryMax > 0) ...[
                  const SizedBox(height: VSDesignTokens.space3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusXS),
                    child: LinearProgressIndicator(
                      value: _retryAttempt / _retryMax,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    'Attempt $_retryAttempt of $_retryMax',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          );
        }
        if (_statusLoading) {
          return Center(
            child: VSLoadingIndicator(message: 'Loading subscription status…'),
          );
        }
        if (_statusError != null) {
          return VSCard(
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            borderRadius: VSDesignTokens.radiusL,
            color: cs.errorContainer,
            child: Text(
              _statusError!,
              style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (_activeTier != null) {
          return VSCard(
            padding: const EdgeInsets.all(VSDesignTokens.space5),
            borderRadius: VSDesignTokens.radiusXL,
            color: cs.primaryContainer.withValues(alpha: 0.5),
            border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
            child: Column(
              children: [
                Icon(Icons.verified_rounded, color: cs.primary, size: VSDesignTokens.iconL),
                const SizedBox(height: VSDesignTokens.space3),
                Text(
                  'Active subscription',
                  style: tt.titleSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: VSTypography.weightSemiBold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _tierLabel(_activeTier),
                  style: tt.headlineSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: VSTypography.weightBold,
                  ),
                ),
                if (_generationLimit != null) ...[
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    'Limit: ${_generationLimit == -1 ? "Unlimited" : _generationLimit}',
                    style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ],
              ],
            ),
          );
        }
        return VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space5),
          borderRadius: VSDesignTokens.radiusXL,
          color: cs.surfaceContainer,
          border: Border.all(color: cs.outlineVariant),
          child: Column(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: cs.primary, size: VSDesignTokens.iconL),
              const SizedBox(height: VSDesignTokens.space3),
              Text(
                'No active subscription',
                style: tt.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: VSTypography.weightSemiBold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VSDesignTokens.space2),
              Text(
                'Pick a plan below to unlock premium features.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _plans() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_iapLoading) {
      return Center(child: VSLoadingIndicator(message: 'Loading plans…'));
    }
    if (_iapError != null && _products.isEmpty) {
      return VSCard(
        padding: const EdgeInsets.all(VSDesignTokens.space5),
        borderRadius: VSDesignTokens.radiusXL,
        color: cs.errorContainer,
        child: Column(
          children: [
            Icon(Icons.error_outline_rounded,
                color: cs.onErrorContainer, size: VSDesignTokens.iconL),
            const SizedBox(height: VSDesignTokens.space3),
            Text(
              'Could not load plans',
              style: tt.titleMedium?.copyWith(
                color: cs.onErrorContainer,
                fontWeight: VSTypography.weightSemiBold,
              ),
            ),
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              _iapError!,
              style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: VSDesignTokens.space3),
          child: Text(
            'Available plans',
            style: tt.titleLarge?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
        ),
        if (_purchaseSuccessMessage != null) ...[
          VSCard(
            padding: const EdgeInsets.all(VSDesignTokens.space4),
            borderRadius: VSDesignTokens.radiusL,
            color: cs.primaryContainer.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: cs.primary),
                const SizedBox(width: VSDesignTokens.space3),
                Expanded(
                  child: Text(
                    _purchaseSuccessMessage!,
                    style: tt.bodyMedium?.copyWith(color: cs.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VSDesignTokens.space4),
        ],
        if (_products.isEmpty)
          const VSEmptyState(
            icon: Icons.shopping_cart_outlined,
            title: 'No plans available right now',
            subtitle: 'Try again later or contact support.',
          )
        else
          ..._products.map((product) {
            final isActive =
                (_activeTier == 'monthly_unlimited_generations' &&
                        product.id == monthlyUnlimitedId) ||
                    (_activeTier == 'monthly_unlimited' &&
                        product.id == legacyMonthlyUnlimitedId);
            return Padding(
              padding: const EdgeInsets.only(bottom: VSDesignTokens.space4),
              child: _PlanCard(
                product: product,
                isActive: isActive,
                isLoading: _purchasePending,
                onPressed: isActive || _purchasePending ? null : () => _buy(product),
              ),
            );
          }),
        if (_iapError != null && _products.isNotEmpty) ...[
          const SizedBox(height: VSDesignTokens.space2),
          Text(
            _iapError!,
            style: tt.bodySmall?.copyWith(color: cs.error),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  void _showSupportDialog() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Contact support'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reach out with the details below and we\'ll help.',
              style: tt.bodyMedium,
            ),
            const SizedBox(height: VSDesignTokens.space3),
            if (_processing.transactionDetails != null) ...[
              Container(
                padding: const EdgeInsets.all(VSDesignTokens.space3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transaction details',
                      style: tt.titleSmall?.copyWith(
                        fontWeight: VSTypography.weightBold,
                      ),
                    ),
                    const SizedBox(height: VSDesignTokens.space2),
                    for (final e in _processing.transactionDetails!.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: VSDesignTokens.space3),
            ],
            Text(
              'Email: support@visionspark.app',
              style: tt.bodyMedium?.copyWith(
                color: cs.primary,
                fontWeight: VSTypography.weightMedium,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              if (_processing.transactionDetails != null) {
                Clipboard.setData(ClipboardData(
                  text: const JsonEncoder.withIndent('  ')
                      .convert(_processing.transactionDetails),
                ));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Details copied to clipboard')),
                );
              }
              Navigator.of(context).pop();
            },
            child: const Text('Copy details'),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final ProductDetails product;
  final bool isActive;
  final bool isLoading;
  final VoidCallback? onPressed;
  const _PlanCard({
    required this.product,
    required this.isActive,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusXL,
      color: isActive
          ? cs.primaryContainer.withValues(alpha: 0.4)
          : cs.surfaceContainer,
      border: Border.all(
        color: isActive ? cs.primary.withValues(alpha: 0.55) : cs.outlineVariant,
        width: isActive ? 1.5 : 1,
      ),
      elevation: isActive ? 4 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isActive) ...[
                Icon(Icons.verified_rounded, color: cs.primary, size: VSDesignTokens.iconM),
                const SizedBox(width: VSDesignTokens.space2),
              ],
              Expanded(
                child: Text(
                  product.title,
                  style: tt.titleLarge?.copyWith(
                    color: isActive ? cs.onPrimaryContainer : cs.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Text(
            product.description,
            style: tt.bodyMedium?.copyWith(
              color: isActive
                  ? cs.onPrimaryContainer.withValues(alpha: 0.85)
                  : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space5),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRICE',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      product.price,
                      style: tt.headlineSmall?.copyWith(
                        color: isActive ? cs.onPrimaryContainer : cs.onSurface,
                        fontWeight: VSTypography.weightBold,
                      ),
                    ),
                  ],
                ),
              ),
              VSButton(
                text: isActive ? 'Active' : 'Subscribe',
                onPressed: onPressed,
                isLoading: isLoading,
                variant: isActive ? VSButtonVariant.outline : VSButtonVariant.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
