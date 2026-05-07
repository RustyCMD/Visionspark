import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Accessibility helpers used across VisionSpark.
///
/// The accessible widgets themselves live in `vs_components.dart` — this file
/// just exposes a few utilities that screens reach for directly.
class VSAccessibility {
  VSAccessibility._();

  static bool prefersReducedMotion(BuildContext context) =>
      MediaQuery.of(context).disableAnimations;

  static bool isHighContrast(BuildContext context) =>
      MediaQuery.of(context).highContrast;

  static bool isLargeTextScale(BuildContext context) =>
      MediaQuery.of(context).textScaler.scale(14) > 16;

  static Duration getAnimationDuration(
    BuildContext context, {
    Duration normal = VSDesignTokens.durationMedium,
    Duration reduced = Duration.zero,
  }) =>
      prefersReducedMotion(context) ? reduced : normal;

  static const double minTouchTargetSize = VSDesignTokens.touchTargetMin;

  static bool meetsTouchTargetSize(Size size) =>
      size.width >= minTouchTargetSize && size.height >= minTouchTargetSize;

  /// Relative luminance per WCAG 2.x.
  static double _relativeLuminance(Color color) {
    double channel(double c) {
      c /= 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055);
    }

    final r = channel(color.r * 255);
    final g = channel(color.g * 255);
    final b = channel(color.b * 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double calculateContrastRatio(Color fg, Color bg) {
    final l1 = _relativeLuminance(fg);
    final l2 = _relativeLuminance(bg);
    final brighter = l1 > l2 ? l1 : l2;
    final darker   = l1 > l2 ? l2 : l1;
    return (brighter + 0.05) / (darker + 0.05);
  }
}
