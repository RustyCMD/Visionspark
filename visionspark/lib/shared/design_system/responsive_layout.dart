import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Layout breakpoint enum.
enum VSBreakpoint { mobile, tablet, desktop, large }

/// Responsive helpers — kept minimal and stateless.
class VSResponsive {
  VSResponsive._();

  static VSBreakpoint of(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < VSDesignTokens.breakpointMobile) return VSBreakpoint.mobile;
    if (w < VSDesignTokens.breakpointTablet) return VSBreakpoint.tablet;
    if (w < VSDesignTokens.breakpointDesktop) return VSBreakpoint.desktop;
    return VSBreakpoint.large;
  }

  static bool isMobile(BuildContext context)  => of(context) == VSBreakpoint.mobile;
  static bool isTablet(BuildContext context)  => of(context) == VSBreakpoint.tablet;
  static bool isDesktop(BuildContext context) =>
      of(context) == VSBreakpoint.desktop || of(context) == VSBreakpoint.large;

  static EdgeInsets getResponsivePadding(BuildContext context) {
    switch (of(context)) {
      case VSBreakpoint.mobile:
        return const EdgeInsets.symmetric(
          horizontal: VSDesignTokens.space5,
          vertical: VSDesignTokens.space4,
        );
      case VSBreakpoint.tablet:
        return const EdgeInsets.symmetric(
          horizontal: VSDesignTokens.space6,
          vertical: VSDesignTokens.space5,
        );
      case VSBreakpoint.desktop:
      case VSBreakpoint.large:
        return const EdgeInsets.symmetric(
          horizontal: VSDesignTokens.space8,
          vertical: VSDesignTokens.space6,
        );
    }
  }

  static EdgeInsets getResponsiveMargin(BuildContext context) {
    switch (of(context)) {
      case VSBreakpoint.mobile:
        return const EdgeInsets.symmetric(horizontal: VSDesignTokens.space4);
      case VSBreakpoint.tablet:
        return const EdgeInsets.symmetric(horizontal: VSDesignTokens.space5);
      case VSBreakpoint.desktop:
      case VSBreakpoint.large:
        return const EdgeInsets.symmetric(horizontal: VSDesignTokens.space6);
    }
  }
}

/// Builder that exposes the current breakpoint.
class VSResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, VSBreakpoint breakpoint) builder;
  const VSResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) => builder(context, VSResponsive.of(context));
}

/// Constrains content to a comfortable max width on large screens.
class VSResponsiveLayout extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  const VSResponsiveLayout({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? VSDesignTokens.maxWidthDesktop,
        ),
        child: child,
      ),
    );
  }
}

/// Vertical spacing that grows with screen size.
class VSResponsiveSpacing extends StatelessWidget {
  final double mobile;
  final double tablet;
  final double desktop;
  const VSResponsiveSpacing({
    super.key,
    this.mobile = VSDesignTokens.space5,
    this.tablet = VSDesignTokens.space6,
    this.desktop = VSDesignTokens.space8,
  });

  @override
  Widget build(BuildContext context) {
    final h = switch (VSResponsive.of(context)) {
      VSBreakpoint.mobile => mobile,
      VSBreakpoint.tablet => tablet,
      VSBreakpoint.desktop || VSBreakpoint.large => desktop,
    };
    return SizedBox(height: h);
  }
}

/// Text whose font size scales by breakpoint.
class VSResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double mobileScale;
  final double tabletScale;
  final double desktopScale;

  const VSResponsiveText({
    super.key,
    required this.text,
    this.baseStyle,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.mobileScale = 1.0,
    this.tabletScale = 1.05,
    this.desktopScale = 1.1,
  });

  @override
  Widget build(BuildContext context) {
    final scale = switch (VSResponsive.of(context)) {
      VSBreakpoint.mobile => mobileScale,
      VSBreakpoint.tablet => tabletScale,
      VSBreakpoint.desktop || VSBreakpoint.large => desktopScale,
    };
    return Text(
      text,
      style: baseStyle?.copyWith(
        fontSize: (baseStyle?.fontSize ?? 14) * scale,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Grid that adjusts column count by breakpoint.
class VSResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final EdgeInsetsGeometry? padding;
  final double childAspectRatio;

  const VSResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 2,
    this.tabletColumns = 3,
    this.desktopColumns = 4,
    this.mainAxisSpacing = VSDesignTokens.space4,
    this.crossAxisSpacing = VSDesignTokens.space4,
    this.padding,
    this.childAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cols = switch (VSResponsive.of(context)) {
      VSBreakpoint.mobile => mobileColumns,
      VSBreakpoint.tablet => tabletColumns,
      VSBreakpoint.desktop || VSBreakpoint.large => desktopColumns,
    };
    return GridView.builder(
      padding: padding,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (_, i) => children[i],
    );
  }
}
