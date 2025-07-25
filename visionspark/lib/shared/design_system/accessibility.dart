import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'design_tokens.dart';

/// Accessibility utilities for VisionSpark
/// 
/// Provides utilities and widgets to ensure the app is accessible to all users,
/// including those using screen readers and other assistive technologies.

class VSAccessibility {
  VSAccessibility._();

  /// Check if the user prefers reduced motion
  static bool prefersReducedMotion(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }

  /// Get the appropriate animation duration based on user preferences
  static Duration getAnimationDuration(
    BuildContext context, {
    Duration normal = VSDesignTokens.durationMedium,
    Duration reduced = Duration.zero,
  }) {
    return prefersReducedMotion(context) ? reduced : normal;
  }

  /// Check if high contrast is enabled
  static bool isHighContrast(BuildContext context) {
    return MediaQuery.of(context).highContrast;
  }

  /// Get text scale factor
  static double getTextScaleFactor(BuildContext context) {
    return MediaQuery.of(context).textScaler.scale(1.0);
  }

  /// Check if text is scaled up significantly
  static bool isLargeTextScale(BuildContext context) {
    return getTextScaleFactor(context) > 1.3;
  }

  /// Ensure minimum touch target size for accessibility
  static Size ensureMinimumTouchTarget(Size size) {
    return Size(
      size.width < VSDesignTokens.touchTargetMin 
        ? VSDesignTokens.touchTargetMin 
        : size.width,
      size.height < VSDesignTokens.touchTargetMin 
        ? VSDesignTokens.touchTargetMin 
        : size.height,
    );
  }

  /// Get appropriate color contrast based on accessibility needs
  static Color getContrastColor(
    BuildContext context,
    Color foreground,
    Color background,
  ) {
    if (isHighContrast(context)) {
      // Return high contrast version
      final luminance = background.computeLuminance();
      return luminance > 0.5 ? Colors.black : Colors.white;
    }
    return foreground;
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
    }
    
    if (hint != null && hint.isNotEmpty) {
      buffer.write(', $hint');
    }
    
    return buffer.toString();
  }
}

/// Accessible button widget with proper semantics and touch targets
class VSAccessibleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? tooltip;
  final bool isSelected;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? borderRadius;

  const VSAccessibleButton({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.tooltip,
    this.isSelected = false,
    this.padding,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget button = Material(
      color: backgroundColor ?? (isSelected 
        ? colorScheme.primaryContainer 
        : Colors.transparent),
      borderRadius: BorderRadius.circular(
        borderRadius ?? VSDesignTokens.radiusM,
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(
          borderRadius ?? VSDesignTokens.radiusM,
        ),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: VSDesignTokens.touchTargetMin,
            minHeight: VSDesignTokens.touchTargetMin,
          ),
          padding: padding ?? const EdgeInsets.all(VSDesignTokens.space3),
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(context).style.copyWith(
              color: foregroundColor ?? (isSelected 
                ? colorScheme.onPrimaryContainer 
                : colorScheme.onSurface),
            ),
            child: IconTheme(
              data: IconThemeData(
                color: foregroundColor ?? (isSelected 
                  ? colorScheme.onPrimaryContainer 
                  : colorScheme.onSurface),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    // Add semantics
    button = Semantics(
      button: true,
      enabled: onPressed != null,
      selected: isSelected,
      label: semanticLabel,
      onTap: onPressed,
      child: button,
    );

    // Add tooltip if provided
    if (tooltip != null) {
      button = Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

/// Accessible card widget with proper semantics
class VSAccessibleCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? semanticHint;
  final bool isSelected;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;

  const VSAccessibleCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.semanticHint,
    this.isSelected = false,
    this.padding,
    this.margin,
    this.elevation,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget card = Card(
      elevation: elevation ?? VSDesignTokens.elevation2,
      margin: margin,
      color: isSelected ? colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
        side: isSelected 
          ? BorderSide(color: colorScheme.primary, width: 2)
          : BorderSide.none,
      ),
      child: Container(
        constraints: onTap != null ? const BoxConstraints(
          minHeight: VSDesignTokens.touchTargetMin,
        ) : null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
            child: Padding(
              padding: padding ?? const EdgeInsets.all(VSDesignTokens.space4),
              child: child,
            ),
          ),
        ),
      ),
    );

    // Add semantics if interactive
    if (onTap != null) {
      card = Semantics(
        button: true,
        enabled: true,
        selected: isSelected,
        label: semanticLabel,
        hint: semanticHint,
        onTap: onTap,
        child: card,
      );
    } else if (semanticLabel != null) {
      card = Semantics(
        label: semanticLabel,
        child: card,
      );
    }

    return card;
  }
}

/// Accessible text field with proper semantics and labels
class VSAccessibleTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final String? semanticLabel;
  final bool obscureText;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final TextAlignVertical? textAlignVertical;

  const VSAccessibleTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.helperText,
    this.errorText,
    this.semanticLabel,
    this.obscureText = false,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.textAlignVertical,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: semanticLabel ?? labelText,
      hint: hintText,
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLines: maxLines,
        minLines: maxLines != null && maxLines! > 1 ? 1 : null,
        maxLength: maxLength,
        onChanged: onChanged,
        onTap: onTap,
        readOnly: readOnly,
        validator: validator,
        textAlignVertical: textAlignVertical ?? (maxLines != null && maxLines! > 1 ? TextAlignVertical.top : null),
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          helperText: helperText,
          errorText: errorText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space4,
            vertical: maxLines != null && maxLines! > 1 ? VSDesignTokens.space2 : VSDesignTokens.space3,
          ),
          alignLabelWithHint: maxLines != null && maxLines! > 1,
        ),
      ),
    );
  }
}
