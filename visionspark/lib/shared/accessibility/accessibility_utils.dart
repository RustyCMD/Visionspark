import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Comprehensive accessibility utilities for VisionSpark
class VSAccessibility {
  /// Minimum touch target size according to accessibility guidelines
  static const double minTouchTargetSize = 48.0;

  /// Minimum color contrast ratio for normal text
  static const double minContrastRatio = 4.5;

  /// Minimum color contrast ratio for large text
  static const double minLargeTextContrastRatio = 3.0;

  /// Check if a widget meets minimum touch target size requirements
  static bool meetsTouchTargetSize(Size size) {
    return size.width >= minTouchTargetSize && size.height >= minTouchTargetSize;
  }

  /// Calculate color contrast ratio between two colors
  static double calculateContrastRatio(Color color1, Color color2) {
    final luminance1 = color1.computeLuminance();
    final luminance2 = color2.computeLuminance();
    
    final lighter = luminance1 > luminance2 ? luminance1 : luminance2;
    final darker = luminance1 > luminance2 ? luminance2 : luminance1;
    
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Check if color combination meets WCAG contrast requirements
  static bool meetsContrastRequirements(Color foreground, Color background, {bool isLargeText = false}) {
    final ratio = calculateContrastRatio(foreground, background);
    final requiredRatio = isLargeText ? minLargeTextContrastRatio : minContrastRatio;
    return ratio >= requiredRatio;
  }

  /// Create semantic label for screen readers
  static String createSemanticLabel({
    required String label,
    String? hint,
    String? value,
    bool isButton = false,
    bool isSelected = false,
    bool isExpanded = false,
  }) {
    final buffer = StringBuffer(label);
    
    if (value != null && value.isNotEmpty) {
      buffer.write(', $value');
    }
    
    if (isButton) {
      buffer.write(', button');
    }
    
    if (isSelected) {
      buffer.write(', selected');
    }
    
    if (isExpanded) {
      buffer.write(', expanded');
    } else if (isExpanded == false) {
      buffer.write(', collapsed');
    }
    
    if (hint != null && hint.isNotEmpty) {
      buffer.write(', $hint');
    }
    
    return buffer.toString();
  }

  /// Announce message to screen readers
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(message, TextDirection.ltr);
  }

  /// Create accessible button with proper semantics
  static Widget createAccessibleButton({
    required Widget child,
    required VoidCallback? onPressed,
    String? semanticLabel,
    String? tooltip,
    bool excludeSemantics = false,
  }) {
    Widget button = child;
    
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip,
        child: button,
      );
    }
    
    if (!excludeSemantics) {
      button = Semantics(
        button: true,
        enabled: onPressed != null,
        label: semanticLabel,
        child: button,
      );
    }
    
    return button;
  }

  /// Create accessible text field with proper semantics
  static Widget createAccessibleTextField({
    required Widget child,
    String? semanticLabel,
    String? hint,
    String? error,
    bool isRequired = false,
  }) {
    return Semantics(
      textField: true,
      label: semanticLabel,
      hint: hint,
      isRequired: isRequired,
      child: child,
    );
  }

  /// Create accessible image with proper semantics
  static Widget createAccessibleImage({
    required Widget child,
    required String semanticLabel,
    bool excludeSemantics = false,
  }) {
    if (excludeSemantics) {
      return ExcludeSemantics(child: child);
    }
    
    return Semantics(
      image: true,
      label: semanticLabel,
      child: child,
    );
  }

  /// Create accessible list item with proper semantics
  static Widget createAccessibleListItem({
    required Widget child,
    String? semanticLabel,
    VoidCallback? onTap,
    bool isSelected = false,
  }) {
    return Semantics(
      button: onTap != null,
      selected: isSelected,
      label: semanticLabel,
      child: child,
    );
  }

  /// Create accessible progress indicator with proper semantics
  static Widget createAccessibleProgress({
    required Widget child,
    String? semanticLabel,
    double? value,
  }) {
    return Semantics(
      label: semanticLabel,
      value: value?.toString(),
      child: child,
    );
  }

  /// Create accessible switch with proper semantics
  static Widget createAccessibleSwitch({
    required Widget child,
    required bool value,
    String? semanticLabel,
  }) {
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: child,
    );
  }

  /// Create accessible slider with proper semantics
  static Widget createAccessibleSlider({
    required Widget child,
    required double value,
    required double min,
    required double max,
    String? semanticLabel,
  }) {
    return Semantics(
      slider: true,
      value: value.toString(),
      increasedValue: (value + 1).clamp(min, max).toString(),
      decreasedValue: (value - 1).clamp(min, max).toString(),
      label: semanticLabel,
      child: child,
    );
  }

  /// Create accessible tab with proper semantics
  static Widget createAccessibleTab({
    required Widget child,
    required bool isSelected,
    required int index,
    required int totalTabs,
    String? semanticLabel,
  }) {
    return Semantics(
      selected: isSelected,
      label: semanticLabel ?? 'Tab ${index + 1} of $totalTabs',
      child: child,
    );
  }

  /// Create accessible dialog with proper semantics
  static Widget createAccessibleDialog({
    required Widget child,
    String? semanticLabel,
    bool isModal = true,
  }) {
    return Semantics(
      scopesRoute: isModal,
      explicitChildNodes: true,
      label: semanticLabel,
      child: child,
    );
  }

  /// Create accessible loading indicator with proper semantics
  static Widget createAccessibleLoading({
    required Widget child,
    String? semanticLabel,
  }) {
    return Semantics(
      label: semanticLabel ?? 'Loading',
      liveRegion: true,
      child: child,
    );
  }

  /// Create accessible error message with proper semantics
  static Widget createAccessibleError({
    required Widget child,
    String? semanticLabel,
  }) {
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: child,
    );
  }

  /// Create accessible success message with proper semantics
  static Widget createAccessibleSuccess({
    required Widget child,
    String? semanticLabel,
  }) {
    return Semantics(
      label: semanticLabel,
      liveRegion: true,
      child: child,
    );
  }

  /// Focus management utilities
  static void requestFocus(BuildContext context, FocusNode focusNode) {
    FocusScope.of(context).requestFocus(focusNode);
  }

  /// Move focus to next focusable element
  static void focusNext(BuildContext context) {
    FocusScope.of(context).nextFocus();
  }

  /// Move focus to previous focusable element
  static void focusPrevious(BuildContext context) {
    FocusScope.of(context).previousFocus();
  }

  /// Clear focus from current element
  static void clearFocus(BuildContext context) {
    FocusScope.of(context).unfocus();
  }

  /// Check if device has screen reader enabled
  static bool isScreenReaderEnabled(BuildContext context) {
    return MediaQuery.of(context).accessibleNavigation;
  }

  /// Check if device has high contrast enabled
  static bool isHighContrastEnabled(BuildContext context) {
    return MediaQuery.of(context).highContrast;
  }

  /// Check if device has reduced motion enabled
  static bool isReducedMotionEnabled(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }

  /// Get text scale factor for accessibility
  static double getTextScaleFactor(BuildContext context) {
    return MediaQuery.of(context).textScaler.scale(1.0);
  }

  /// Check if text scale factor is large
  static bool isLargeTextScale(BuildContext context) {
    return getTextScaleFactor(context) > 1.3;
  }

  /// Create accessible route announcements
  static void announceRouteChange(BuildContext context, String routeName) {
    announce(context, 'Navigated to $routeName');
  }

  /// Create accessible action announcements
  static void announceAction(BuildContext context, String action) {
    announce(context, action);
  }

  /// Create accessible state change announcements
  static void announceStateChange(BuildContext context, String stateChange) {
    announce(context, stateChange);
  }
}

/// Accessibility testing utilities
class VSAccessibilityTesting {
  /// Test color contrast for accessibility compliance
  static Map<String, dynamic> testColorContrast(Color foreground, Color background) {
    final ratio = VSAccessibility.calculateContrastRatio(foreground, background);
    return {
      'ratio': ratio,
      'passesAA': ratio >= 4.5,
      'passesAAA': ratio >= 7.0,
      'passesAALarge': ratio >= 3.0,
      'passesAAALarge': ratio >= 4.5,
    };
  }

  /// Test touch target sizes for accessibility compliance
  static Map<String, dynamic> testTouchTargetSize(Size size) {
    return {
      'width': size.width,
      'height': size.height,
      'meetsMinimum': VSAccessibility.meetsTouchTargetSize(size),
      'minimumRequired': VSAccessibility.minTouchTargetSize,
    };
  }

  /// Generate accessibility report for a widget tree
  static Map<String, dynamic> generateAccessibilityReport(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return {
      'screenReader': mediaQuery.accessibleNavigation,
      'highContrast': mediaQuery.highContrast,
      'reducedMotion': mediaQuery.disableAnimations,
      'textScaleFactor': mediaQuery.textScaler.scale(1.0),
      'isLargeText': VSAccessibility.isLargeTextScale(context),
      'devicePixelRatio': mediaQuery.devicePixelRatio,
      'screenSize': {
        'width': mediaQuery.size.width,
        'height': mediaQuery.size.height,
      },
    };
  }
}
