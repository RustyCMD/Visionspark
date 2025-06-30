import 'package:flutter/material.dart';

/// PageContainer is a helper widget that centers its [child] in the
/// available viewport and constrains the width to [maxWidth].
///
/// This makes large-screen layouts look less stretched while keeping
/// mobile screens unaffected. By default, no extra padding is applied
/// so existing screen padding can be reused.
class PageContainer extends StatelessWidget {
  final Widget child;

  /// Maximum width that the child can take. Defaults to 680 which looks good
  /// on tablets and desktop screens while still allowing generous whitespace.
  final double maxWidth;

  /// Optional inner padding. If null, no extra padding is applied – allowing
  /// callers to keep their own padding logic.
  final EdgeInsetsGeometry? padding;

  const PageContainer({
    super.key,
    required this.child,
    this.maxWidth = 680,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final content = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: content,
      ),
    );
  }
}