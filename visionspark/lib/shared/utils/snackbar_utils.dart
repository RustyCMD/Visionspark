import 'package:flutter/material.dart';
import '../design_system/design_tokens.dart';

/// Enhanced snackbar utilities with consistent design and better UX
class VSSnackbar {
  VSSnackbar._();

  static void showError(BuildContext context, String message, {Duration? duration}) {
    _showSnackbar(
      context,
      message: message,
      type: _SnackbarType.error,
      duration: duration,
    );
  }

  static void showSuccess(BuildContext context, String message, {Duration? duration}) {
    _showSnackbar(
      context,
      message: message,
      type: _SnackbarType.success,
      duration: duration,
    );
  }

  static void showInfo(BuildContext context, String message, {Duration? duration}) {
    _showSnackbar(
      context,
      message: message,
      type: _SnackbarType.info,
      duration: duration,
    );
  }

  static void showWarning(BuildContext context, String message, {Duration? duration}) {
    _showSnackbar(
      context,
      message: message,
      type: _SnackbarType.warning,
      duration: duration,
    );
  }

  static void _showSnackbar(
    BuildContext context, {
    required String message,
    required _SnackbarType type,
    Duration? duration,
  }) {
    if (!context.mounted) return;

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Remove any existing snackbar
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    // Configure colors and icons based on type
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (type) {
      case _SnackbarType.error:
        backgroundColor = colorScheme.errorContainer;
        textColor = colorScheme.onErrorContainer;
        icon = Icons.error_outline_rounded;
        break;
      case _SnackbarType.success:
        backgroundColor = VSColors.success;
        textColor = Colors.white;
        icon = Icons.check_circle_outline_rounded;
        break;
      case _SnackbarType.info:
        backgroundColor = VSColors.info;
        textColor = Colors.white;
        icon = Icons.info_outline_rounded;
        break;
      case _SnackbarType.warning:
        backgroundColor = VSColors.warning;
        textColor = Colors.white;
        icon = Icons.warning_amber_rounded;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              icon,
              color: textColor,
              size: VSDesignTokens.iconS,
            ),
            const SizedBox(width: VSDesignTokens.space3),
            Expanded(
              child: Text(
                message,
                style: textTheme.bodyMedium?.copyWith(
                  color: textColor,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        ),
        margin: const EdgeInsets.all(VSDesignTokens.space4),
        duration: duration ?? const Duration(seconds: 4),
        elevation: VSDesignTokens.elevation4,
      ),
    );
  }
}

enum _SnackbarType { error, success, info, warning }

// Backward compatibility functions
void showErrorSnackbar(BuildContext context, String message) {
  VSSnackbar.showError(context, message);
}

void showSuccessSnackbar(BuildContext context, String message) {
  VSSnackbar.showSuccess(context, message);
}