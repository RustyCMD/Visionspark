import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// VisionSpark — Aurora component kit.
///
/// Surface (`VSCard`), action (`VSButton`), feedback (`VSLoadingIndicator`,
/// `VSEmptyState`) and the accessible primitives that compose them.

// ─────────────────────────────────────────────────────────────────────────────
// VSCard
// ─────────────────────────────────────────────────────────────────────────────

class VSCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double? elevation;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final Gradient? gradient;

  const VSCard({
    super.key,
    required this.child,
    this.color,
    this.elevation,
    this.borderRadius = VSDesignTokens.radiusL,
    this.padding,
    this.margin,
    this.border,
    this.boxShadow,
    this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);
    final defaultShadow = (elevation == null || elevation == 0)
        ? null
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: (elevation ?? 0) * 2,
              offset: Offset(0, (elevation ?? 0) / 2),
            ),
          ];

    final card = AnimatedContainer(
      duration: VSDesignTokens.durationFast,
      margin: margin,
      padding: padding ?? const EdgeInsets.all(VSDesignTokens.space4),
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? cs.surfaceContainer) : null,
        gradient: gradient,
        borderRadius: radius,
        border: border,
        boxShadow: boxShadow ?? defaultShadow,
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: card,
      ),
    );
  }
}

class VSAccessibleCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? semanticHint;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final double borderRadius;
  final Color? color;
  final BoxBorder? border;

  const VSAccessibleCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.semanticHint,
    this.padding,
    this.margin,
    this.elevation,
    this.borderRadius = VSDesignTokens.radiusL,
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      hint: semanticHint,
      child: VSCard(
        onTap: onTap,
        padding: padding,
        margin: margin,
        elevation: elevation,
        borderRadius: borderRadius,
        color: color,
        border: border,
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VSButton
// ─────────────────────────────────────────────────────────────────────────────

enum VSButtonVariant { primary, secondary, outline, ghost, danger }
enum VSButtonSize { small, medium, large }

class VSButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool isFullWidth;
  final VSButtonVariant variant;
  final VSButtonSize size;

  const VSButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.variant = VSButtonVariant.primary,
    this.size = VSButtonSize.medium,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final (vertical, horizontal, fontSize, iconSize) = switch (size) {
      VSButtonSize.small  => (10.0, VSDesignTokens.space4, 14.0, 16.0),
      VSButtonSize.medium => (14.0, VSDesignTokens.space5, 15.0, 18.0),
      VSButtonSize.large  => (18.0, VSDesignTokens.space6, 16.0, 20.0),
    };

    final disabled = onPressed == null || isLoading;

    Color bg, fg;
    BorderSide? border;

    switch (variant) {
      case VSButtonVariant.primary:
        bg = cs.primary;
        fg = cs.onPrimary;
        break;
      case VSButtonVariant.secondary:
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case VSButtonVariant.outline:
        bg = Colors.transparent;
        fg = cs.primary;
        border = BorderSide(color: cs.outline.withValues(alpha: 0.6));
        break;
      case VSButtonVariant.ghost:
        bg = Colors.transparent;
        fg = cs.primary;
        break;
      case VSButtonVariant.danger:
        bg = cs.error;
        fg = cs.onError;
        break;
    }

    if (disabled) {
      bg = bg == Colors.transparent ? bg : bg.withValues(alpha: 0.4);
      fg = fg.withValues(alpha: 0.6);
    }

    final child = isLoading
        ? SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(fg),
            ),
          )
        : Row(
            mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTheme(
                  data: IconThemeData(color: fg, size: iconSize),
                  child: icon!,
                ),
                const SizedBox(width: VSDesignTokens.space2),
              ],
              Text(
                text,
                style: tt.labelLarge?.copyWith(
                  color: fg,
                  fontSize: fontSize,
                  fontWeight: VSTypography.weightSemiBold,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          );

    final radius = BorderRadius.circular(VSDesignTokens.radiusM);

    return Semantics(
      button: true,
      enabled: !disabled,
      child: SizedBox(
        width: isFullWidth ? double.infinity : null,
        child: Material(
          color: bg,
          borderRadius: radius,
          shape: border == null
              ? RoundedRectangleBorder(borderRadius: radius)
              : RoundedRectangleBorder(
                  borderRadius: radius,
                  side: border,
                ),
          child: InkWell(
            onTap: disabled ? null : onPressed,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: vertical,
                horizontal: horizontal,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class VSAccessibleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? tooltip;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double borderRadius;

  const VSAccessibleButton({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.tooltip,
    this.padding,
    this.backgroundColor,
    this.borderRadius = VSDesignTokens.radiusM,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    Widget result = Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onPressed,
        borderRadius: radius,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(VSDesignTokens.space2),
          child: child,
        ),
      ),
    );

    if (tooltip != null) result = Tooltip(message: tooltip!, child: result);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: result,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VSAccessibleTextField
// ─────────────────────────────────────────────────────────────────────────────

class VSAccessibleTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? labelText;
  final String? hintText;
  final String? semanticLabel;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextAlignVertical? textAlignVertical;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final bool autofocus;

  const VSAccessibleTextField({
    super.key,
    this.controller,
    this.labelText,
    this.hintText,
    this.semanticLabel,
    this.prefixIcon,
    this.suffixIcon,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.textAlignVertical,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? labelText,
      textField: true,
      child: TextFormField(
        controller: controller,
        maxLines: obscureText ? 1 : maxLines,
        minLines: minLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textAlignVertical: textAlignVertical,
        obscureText: obscureText,
        autofocus: autofocus,
        validator: validator,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          counterText: maxLength == null ? null : '',
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VSLoadingIndicator
// ─────────────────────────────────────────────────────────────────────────────

class VSLoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;
  final Color? color;

  const VSLoadingIndicator({
    super.key,
    this.message,
    this.size = VSDesignTokens.iconM,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final c = color ?? cs.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation(c),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: VSDesignTokens.space3),
          Text(
            message!,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VSEmptyState
// ─────────────────────────────────────────────────────────────────────────────

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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(VSDesignTokens.space6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(VSDesignTokens.space5),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: VSDesignTokens.iconL, color: cs.primary),
          ),
          const SizedBox(height: VSDesignTokens.space5),
          Text(
            title,
            style: tt.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              subtitle!,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: VSDesignTokens.space5),
            action!,
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VSAuroraBackground — branded gradient backdrop used on auth screens.
// ─────────────────────────────────────────────────────────────────────────────

class VSAuroraBackground extends StatelessWidget {
  final Widget child;
  const VSAuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: cs.surface),
        ),
        Positioned(
          top: -160,
          right: -120,
          child: _AuroraBlob(
            size: 380,
            colors: [cs.primary.withValues(alpha: 0.45), cs.primary.withValues(alpha: 0)],
          ),
        ),
        Positioned(
          bottom: -180,
          left: -140,
          child: _AuroraBlob(
            size: 420,
            colors: [cs.secondary.withValues(alpha: 0.35), cs.secondary.withValues(alpha: 0)],
          ),
        ),
        Positioned(
          top: 240,
          left: -80,
          child: _AuroraBlob(
            size: 260,
            colors: [cs.tertiary.withValues(alpha: 0.25), cs.tertiary.withValues(alpha: 0)],
          ),
        ),
        child,
      ],
    );
  }
}

class _AuroraBlob extends StatelessWidget {
  final double size;
  final List<Color> colors;
  const _AuroraBlob({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VSSectionHeader — icon + title row reused across screens.
// ─────────────────────────────────────────────────────────────────────────────

class VSSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const VSSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(VSDesignTokens.space3),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
          ),
          child: Icon(icon, color: cs.primary, size: VSDesignTokens.iconM),
        ),
        const SizedBox(width: VSDesignTokens.space4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: VSTypography.weightBold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
