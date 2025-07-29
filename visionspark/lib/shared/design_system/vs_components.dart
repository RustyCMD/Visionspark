import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// VisionSpark Shared UI Components
/// 
/// This file contains reusable UI components that maintain consistency
/// across the entire VisionSpark application.

// ============================================================================
// CARDS
// ============================================================================

class VSCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final Color? color;
  final double? borderRadius;
  final Border? border;
  final VoidCallback? onTap;
  final bool isInteractive;

  const VSCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.color,
    this.borderRadius,
    this.border,
    this.onTap,
    this.isInteractive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    Widget cardContent = Container(
      padding: padding ?? const EdgeInsets.all(VSDesignTokens.space4),
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(borderRadius ?? VSDesignTokens.radiusL),
        border: border,
        boxShadow: elevation != null ? [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: elevation! * 2,
            offset: Offset(0, elevation! / 2),
          ),
        ] : null,
      ),
      child: child,
    );

    if (onTap != null || isInteractive) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius ?? VSDesignTokens.radiusL),
          child: cardContent,
        ),
      );
    }

    return cardContent;
  }
}

// ============================================================================
// BUTTONS
// ============================================================================

class VSButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final VSButtonVariant variant;
  final VSButtonSize size;
  final Widget? icon;
  final bool isLoading;
  final bool isFullWidth;

  const VSButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = VSButtonVariant.primary,
    this.size = VSButtonSize.medium,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Size configurations
    EdgeInsetsGeometry padding;
    double fontSize;
    double iconSize;
    
    switch (size) {
      case VSButtonSize.small:
        padding = const EdgeInsets.symmetric(
          horizontal: VSDesignTokens.space3,
          vertical: VSDesignTokens.space2,
        );
        fontSize = VSTypography.fontSize14;
        iconSize = VSDesignTokens.iconS;
        break;
      case VSButtonSize.medium:
        padding = const EdgeInsets.symmetric(
          horizontal: VSDesignTokens.space4,
          vertical: VSDesignTokens.space3,
        );
        fontSize = VSTypography.fontSize16;
        iconSize = VSDesignTokens.iconM;
        break;
      case VSButtonSize.large:
        padding = const EdgeInsets.symmetric(
          horizontal: VSDesignTokens.space6,
          vertical: VSDesignTokens.space4,
        );
        fontSize = VSTypography.fontSize18;
        iconSize = VSDesignTokens.iconL;
        break;
    }

    // Variant configurations
    Color backgroundColor;
    Color foregroundColor;
    Color? borderColor;
    
    switch (variant) {
      case VSButtonVariant.primary:
        backgroundColor = colorScheme.primary;
        foregroundColor = colorScheme.onPrimary;
        borderColor = null;
        break;
      case VSButtonVariant.secondary:
        backgroundColor = colorScheme.secondary;
        foregroundColor = colorScheme.onSecondary;
        borderColor = null;
        break;
      case VSButtonVariant.outline:
        backgroundColor = Colors.transparent;
        foregroundColor = colorScheme.primary;
        borderColor = colorScheme.primary;
        break;
      case VSButtonVariant.ghost:
        backgroundColor = Colors.transparent;
        foregroundColor = colorScheme.onSurface;
        borderColor = null;
        break;
      case VSButtonVariant.danger:
        backgroundColor = colorScheme.error;
        foregroundColor = colorScheme.onError;
        borderColor = null;
        break;
    }

    Widget buttonChild = LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        if (isLoading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: foregroundColor,
            ),
          ),
          const SizedBox(width: VSDesignTokens.space3),
        ] else if (icon != null) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: IconTheme(
              data: IconThemeData(
                color: foregroundColor,
                size: iconSize,
              ),
              child: icon!,
            ),
          ),
          const SizedBox(width: VSDesignTokens.space3),
        ],
        Flexible(
          child: Text(
            text,
            style: textTheme.labelLarge?.copyWith(
              color: foregroundColor,
              fontSize: fontSize,
              fontWeight: VSTypography.weightMedium,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
      },
    );

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
            side: borderColor != null 
              ? BorderSide(color: borderColor, width: 1.5)
              : BorderSide.none,
          ),
          elevation: variant == VSButtonVariant.ghost || variant == VSButtonVariant.outline 
            ? 0 
            : VSDesignTokens.elevation2,
        ),
        child: buttonChild,
      ),
    );
  }
}

enum VSButtonVariant { primary, secondary, outline, ghost, danger }
enum VSButtonSize { small, medium, large }

// ============================================================================
// LOADING INDICATORS
// ============================================================================

class VSLoadingIndicator extends StatelessWidget {
  final double? size;
  final Color? color;
  final String? message;

  const VSLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size ?? VSDesignTokens.iconL,
          height: size ?? VSDesignTokens.iconL,
          child: CircularProgressIndicator(
            color: color ?? colorScheme.primary,
            strokeWidth: 3,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: VSDesignTokens.space3),
          Text(
            message!,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// EMPTY STATES
// ============================================================================

class VSEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const VSEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: VSDesignTokens.space3,
        vertical: VSDesignTokens.space2, // Even less vertical padding
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: VSDesignTokens.iconM, // Even smaller icon
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(height: VSDesignTokens.space1), // Minimal spacing
          Text(
            title,
            style: textTheme.titleSmall?.copyWith( // Even smaller title
              color: colorScheme.onSurface,
              fontWeight: VSTypography.weightMedium,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2), // Tiny spacing
            Text(
              subtitle!,
              style: textTheme.labelMedium?.copyWith( // Smallest subtitle
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: VSDesignTokens.space1), // Minimal spacing
            action!,
          ],
        ],
      ),
    );
  }
}
