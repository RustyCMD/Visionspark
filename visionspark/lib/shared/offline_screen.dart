import 'package:flutter/material.dart';
import 'design_system/design_system.dart';

class OfflineScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const OfflineScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: VSAuroraBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(VSDesignTokens.space8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(VSDesignTokens.space6),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      size: VSDesignTokens.iconXL,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space6),
                  Text(
                    'You\'re offline',
                    style: tt.headlineSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: VSTypography.weightBold,
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Text(
                    'Check your Wi-Fi or mobile data and try again.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VSDesignTokens.space8),
                  VSButton(
                    text: 'Retry',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: onRetry,
                    size: VSButtonSize.large,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
