import 'package:flutter/material.dart';
import '../design_system/design_tokens.dart';

/// VisionSpark — themed snackbars.
class VSSnackbar {
  VSSnackbar._();

  static void showError(BuildContext c, String m, {Duration? d})   => _show(c, m, _Kind.error,   d);
  static void showSuccess(BuildContext c, String m, {Duration? d}) => _show(c, m, _Kind.success, d);
  static void showInfo(BuildContext c, String m, {Duration? d})    => _show(c, m, _Kind.info,    d);
  static void showWarning(BuildContext c, String m, {Duration? d}) => _show(c, m, _Kind.warning, d);

  static void _show(BuildContext context, String message, _Kind kind, Duration? duration) {
    if (!context.mounted) return;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final (bg, fg, icon) = switch (kind) {
      _Kind.error   => (cs.errorContainer,    cs.onErrorContainer, Icons.error_outline_rounded),
      _Kind.success => (VSColors.success,     Colors.white,        Icons.check_circle_rounded),
      _Kind.info    => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.info_outline_rounded),
      _Kind.warning => (VSColors.warning,     Colors.white,        Icons.warning_amber_rounded),
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(VSDesignTokens.space4),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        ),
        duration: duration ?? const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(icon, color: fg, size: VSDesignTokens.iconS),
            const SizedBox(width: VSDesignTokens.space3),
            Expanded(
              child: Text(
                message,
                style: tt.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Kind { error, success, info, warning }

void showErrorSnackbar(BuildContext context, String message)   => VSSnackbar.showError(context, message);
void showSuccessSnackbar(BuildContext context, String message) => VSSnackbar.showSuccess(context, message);
