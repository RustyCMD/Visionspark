import 'package:flutter/material.dart';
import '../design_system/design_system.dart';

/// Enum representing different subscription processing phases
enum SubscriptionProcessingPhase {
  validating('Validating Purchase', 'Verifying your purchase with Google Play...', 0.2),
  acknowledging('Acknowledging Purchase', 'Confirming your purchase with Google Play...', 0.4),
  updatingProfile('Updating Account', 'Activating your subscription benefits...', 0.7),
  completing('Finalizing', 'Almost done! Preparing your account...', 0.9),
  completed('Complete', 'Your subscription is now active!', 1.0);

  const SubscriptionProcessingPhase(this.title, this.description, this.progress);

  final String title;
  final String description;
  final double progress;
}

/// Widget that displays subscription processing status with Material Design 3 styling
class SubscriptionProcessingWidget extends StatefulWidget {
  final SubscriptionProcessingPhase currentPhase;
  final String? estimatedTimeRemaining;
  final String? additionalMessage;
  final VoidCallback? onContactSupport;
  final bool showContactSupport;
  final Map<String, dynamic>? transactionDetails;

  const SubscriptionProcessingWidget({
    super.key,
    required this.currentPhase,
    this.estimatedTimeRemaining,
    this.additionalMessage,
    this.onContactSupport,
    this.showContactSupport = false,
    this.transactionDetails,
  });

  @override
  State<SubscriptionProcessingWidget> createState() => _SubscriptionProcessingWidgetState();
}

class _SubscriptionProcessingWidgetState extends State<SubscriptionProcessingWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: widget.currentPhase.progress,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeOutCubic,
    ));
    
    _progressController.forward();
  }

  @override
  void didUpdateWidget(SubscriptionProcessingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.currentPhase != widget.currentPhase) {
      _progressAnimation = Tween<double>(
        begin: oldWidget.currentPhase.progress,
        end: widget.currentPhase.progress,
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeOutCubic,
      ));
      
      _progressController.reset();
      _progressController.forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return VSCard(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      elevation: VSDesignTokens.elevation2,
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Processing Icon with Pulse Animation
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    widget.currentPhase == SubscriptionProcessingPhase.completed
                        ? Icons.check_circle
                        : Icons.sync,
                    size: 40,
                    color: colorScheme.primary,
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: VSDesignTokens.space4),
          
          // Phase Title
          Text(
            widget.currentPhase.title,
            style: textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightBold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: VSDesignTokens.space2),
          
          // Phase Description
          Text(
            widget.currentPhase.description,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          
          if (widget.additionalMessage != null) ...[
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              widget.additionalMessage!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          
          const SizedBox(height: VSDesignTokens.space4),
          
          // Progress Bar
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return Column(
                children: [
                  LinearProgressIndicator(
                    value: _progressAnimation.value,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    minHeight: 6,
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    '${(_progressAnimation.value * 100).round()}% Complete',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: VSTypography.weightMedium,
                    ),
                  ),
                ],
              );
            },
          ),
          
          if (widget.estimatedTimeRemaining != null) ...[
            const SizedBox(height: VSDesignTokens.space3),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: VSDesignTokens.space3,
                vertical: VSDesignTokens.space2,
              ),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: VSDesignTokens.space1),
                  Text(
                    'Estimated time: ${widget.estimatedTimeRemaining}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                      fontWeight: VSTypography.weightMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (widget.showContactSupport) ...[
            const SizedBox(height: VSDesignTokens.space4),
            VSButton(
              text: 'Contact Support',
              onPressed: widget.onContactSupport,
              variant: VSButtonVariant.outline,
              size: VSButtonSize.medium,
              icon: const Icon(Icons.support_agent),
            ),
          ],
        ],
      ),
    );
  }
}

/// Widget for displaying subscription processing completion with success animation
class SubscriptionCompletionWidget extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback? onContinue;
  final Map<String, dynamic>? subscriptionDetails;

  const SubscriptionCompletionWidget({
    super.key,
    required this.title,
    required this.message,
    this.onContinue,
    this.subscriptionDetails,
  });

  @override
  State<SubscriptionCompletionWidget> createState() => _SubscriptionCompletionWidgetState();
}

class _SubscriptionCompletionWidgetState extends State<SubscriptionCompletionWidget>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));
    
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return VSCard(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      elevation: VSDesignTokens.elevation2,
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Success Icon with Scale Animation
          AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 60,
                    color: colorScheme.onPrimary,
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: VSDesignTokens.space4),
          
          Text(
            widget.title,
            style: textTheme.headlineMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightBold,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: VSDesignTokens.space2),
          
          Text(
            widget.message,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          
          if (widget.subscriptionDetails != null) ...[
            const SizedBox(height: VSDesignTokens.space4),
            Container(
              padding: const EdgeInsets.all(VSDesignTokens.space3),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
              ),
              child: Column(
                children: [
                  Text(
                    'Subscription Details',
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: VSTypography.weightBold,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  ...widget.subscriptionDetails!.entries.map((entry) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            entry.key,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            entry.value.toString(),
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: VSTypography.weightMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (widget.onContinue != null) ...[
            const SizedBox(height: VSDesignTokens.space4),
            VSButton(
              text: 'Continue',
              onPressed: widget.onContinue,
              variant: VSButtonVariant.primary,
              size: VSButtonSize.large,
            ),
          ],
        ],
      ),
    );
  }
}
