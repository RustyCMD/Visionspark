import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Responsive layout utilities for VisionSpark
/// 
/// Provides utilities for creating responsive layouts that adapt to different
/// screen sizes and orientations.

class VSResponsive {
  VSResponsive._();

  /// Get the current screen breakpoint
  static VSBreakpoint getBreakpoint(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= VSDesignTokens.breakpointLarge) {
      return VSBreakpoint.large;
    } else if (width >= VSDesignTokens.breakpointDesktop) {
      return VSBreakpoint.desktop;
    } else if (width >= VSDesignTokens.breakpointTablet) {
      return VSBreakpoint.tablet;
    } else {
      return VSBreakpoint.mobile;
    }
  }

  /// Check if the current screen is mobile
  static bool isMobile(BuildContext context) {
    return getBreakpoint(context) == VSBreakpoint.mobile;
  }

  /// Check if the current screen is tablet
  static bool isTablet(BuildContext context) {
    return getBreakpoint(context) == VSBreakpoint.tablet;
  }

  /// Check if the current screen is desktop or larger
  static bool isDesktop(BuildContext context) {
    final breakpoint = getBreakpoint(context);
    return breakpoint == VSBreakpoint.desktop || breakpoint == VSBreakpoint.large;
  }

  /// Get responsive padding based on screen size
  static EdgeInsetsGeometry getResponsivePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(VSDesignTokens.space4);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(VSDesignTokens.space6);
    } else {
      return const EdgeInsets.all(VSDesignTokens.space8);
    }
  }

  /// Get responsive margin based on screen size
  static EdgeInsetsGeometry getResponsiveMargin(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: VSDesignTokens.space4);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: VSDesignTokens.space8);
    } else {
      return const EdgeInsets.symmetric(horizontal: VSDesignTokens.space12);
    }
  }

  /// Get responsive grid columns based on screen size
  static int getGridColumns(BuildContext context) {
    if (isMobile(context)) {
      return 2;
    } else if (isTablet(context)) {
      return 3;
    } else {
      return 4;
    }
  }

  /// Get responsive content max width
  static double getContentMaxWidth(BuildContext context) {
    if (isMobile(context)) {
      return VSDesignTokens.maxWidthMobile;
    } else if (isTablet(context)) {
      return VSDesignTokens.maxWidthTablet;
    } else {
      return VSDesignTokens.maxWidthDesktop;
    }
  }

  /// Get responsive font size scaling
  static double getFontScale(BuildContext context) {
    if (isMobile(context)) {
      return 0.9;
    } else if (isTablet(context)) {
      return 1.0;
    } else {
      return 1.1;
    }
  }

  /// Get responsive icon size
  static double getIconSize(BuildContext context, double baseSize) {
    final scale = getFontScale(context);
    return baseSize * scale;
  }

  /// Get responsive button height
  static double getButtonHeight(BuildContext context) {
    if (isMobile(context)) {
      return 48.0;
    } else if (isTablet(context)) {
      return 52.0;
    } else {
      return 56.0;
    }
  }

  /// Get responsive card elevation
  static double getCardElevation(BuildContext context, double baseElevation) {
    if (isMobile(context)) {
      return baseElevation * 0.8;
    } else {
      return baseElevation;
    }
  }

  /// Get responsive border radius
  static double getBorderRadius(BuildContext context, double baseRadius) {
    if (isMobile(context)) {
      return baseRadius * 0.8;
    } else {
      return baseRadius;
    }
  }

  /// Check if device is in landscape orientation
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Check if device is in portrait orientation
  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  /// Get safe area padding
  static EdgeInsets getSafeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }

  /// Get responsive app bar height
  static double getAppBarHeight(BuildContext context) {
    if (isMobile(context)) {
      return kToolbarHeight;
    } else {
      return kToolbarHeight + 8.0;
    }
  }
}

enum VSBreakpoint { mobile, tablet, desktop, large }

/// Responsive navigation widget that adapts between bottom navigation and rail
class VSResponsiveNavigation extends StatelessWidget {
  final List<VSNavigationItem> items;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final Widget? leading;
  final Widget? trailing;

  const VSResponsiveNavigation({
    super.key,
    required this.items,
    required this.selectedIndex,
    this.onDestinationSelected,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return VSResponsiveBuilder(
      builder: (context, breakpoint) {
        if (breakpoint == VSBreakpoint.mobile) {
          return BottomNavigationBar(
            currentIndex: selectedIndex,
            onTap: onDestinationSelected,
            type: BottomNavigationBarType.fixed,
            items: items.map((item) => BottomNavigationBarItem(
              icon: item.icon,
              activeIcon: item.activeIcon ?? item.icon,
              label: item.label,
              tooltip: item.tooltip,
            )).toList(),
          );
        } else {
          return NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            leading: leading,
            trailing: trailing,
            extended: breakpoint == VSBreakpoint.desktop || breakpoint == VSBreakpoint.large,
            destinations: items.map((item) => NavigationRailDestination(
              icon: item.icon,
              selectedIcon: item.activeIcon ?? item.icon,
              label: Text(item.label),
            )).toList(),
          );
        }
      },
    );
  }
}

class VSNavigationItem {
  final Widget icon;
  final Widget? activeIcon;
  final String label;
  final String? tooltip;

  const VSNavigationItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.tooltip,
  });
}

/// Responsive dialog widget that adapts between full-screen and dialog on different screen sizes
class VSResponsiveDialog extends StatelessWidget {
  final Widget child;
  final String? title;
  final List<Widget>? actions;
  final bool forceFullScreen;
  final EdgeInsetsGeometry? contentPadding;

  const VSResponsiveDialog({
    super.key,
    required this.child,
    this.title,
    this.actions,
    this.forceFullScreen = false,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return VSResponsiveBuilder(
      builder: (context, breakpoint) {
        final shouldUseFullScreen = forceFullScreen || breakpoint == VSBreakpoint.mobile;

        if (shouldUseFullScreen) {
          return Scaffold(
            appBar: AppBar(
              title: title != null ? Text(title!) : null,
              actions: actions,
            ),
            body: Padding(
              padding: contentPadding ?? VSResponsive.getResponsivePadding(context),
              child: child,
            ),
          );
        } else {
          return Dialog(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: VSResponsive.getContentMaxWidth(context) * 0.8,
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null || actions != null)
                    Padding(
                      padding: const EdgeInsets.all(VSDesignTokens.space4),
                      child: Row(
                        children: [
                          if (title != null)
                            Expanded(
                              child: Text(
                                title!,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          if (actions != null) ...actions!,
                        ],
                      ),
                    ),
                  Flexible(
                    child: Padding(
                      padding: contentPadding ?? const EdgeInsets.all(VSDesignTokens.space4),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  /// Show responsive dialog
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    List<Widget>? actions,
    bool forceFullScreen = false,
    EdgeInsetsGeometry? contentPadding,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => VSResponsiveDialog(
        title: title,
        actions: actions,
        forceFullScreen: forceFullScreen,
        contentPadding: contentPadding,
        child: child,
      ),
    );
  }
}

/// Responsive builder widget that provides different layouts for different screen sizes
class VSResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, VSBreakpoint breakpoint) builder;

  const VSResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final breakpoint = VSResponsive.getBreakpoint(context);
    return builder(context, breakpoint);
  }
}

/// Responsive layout widget that constrains content width and centers it
class VSResponsiveLayout extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool centerContent;

  const VSResponsiveLayout({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.centerContent = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveMaxWidth = maxWidth ?? VSResponsive.getContentMaxWidth(context);
    final effectivePadding = padding ?? VSResponsive.getResponsivePadding(context);

    Widget content = Container(
      constraints: BoxConstraints(maxWidth: effectiveMaxWidth),
      padding: effectivePadding,
      child: child,
    );

    if (centerContent) {
      content = Center(child: content);
    }

    return content;
  }
}

/// Responsive grid widget that adapts column count based on screen size
class VSResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int? mobileColumns;
  final int? tabletColumns;
  final int? desktopColumns;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final EdgeInsetsGeometry? padding;
  final double childAspectRatio;

  const VSResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns,
    this.tabletColumns,
    this.desktopColumns,
    this.mainAxisSpacing = VSDesignTokens.space4,
    this.crossAxisSpacing = VSDesignTokens.space4,
    this.padding,
    this.childAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return VSResponsiveBuilder(
      builder: (context, breakpoint) {
        int columns;
        switch (breakpoint) {
          case VSBreakpoint.mobile:
            columns = mobileColumns ?? 2;
            break;
          case VSBreakpoint.tablet:
            columns = tabletColumns ?? 3;
            break;
          case VSBreakpoint.desktop:
          case VSBreakpoint.large:
            columns = desktopColumns ?? 4;
            break;
        }

        return GridView.builder(
          padding: padding ?? VSResponsive.getResponsivePadding(context),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
  }
}

/// Responsive spacing widget that provides different spacing based on screen size
class VSResponsiveSpacing extends StatelessWidget {
  final double? mobile;
  final double? tablet;
  final double? desktop;
  final Axis direction;

  const VSResponsiveSpacing({
    super.key,
    this.mobile,
    this.tablet,
    this.desktop,
    this.direction = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    return VSResponsiveBuilder(
      builder: (context, breakpoint) {
        double spacing;
        switch (breakpoint) {
          case VSBreakpoint.mobile:
            spacing = mobile ?? VSDesignTokens.space4;
            break;
          case VSBreakpoint.tablet:
            spacing = tablet ?? VSDesignTokens.space6;
            break;
          case VSBreakpoint.desktop:
          case VSBreakpoint.large:
            spacing = desktop ?? VSDesignTokens.space8;
            break;
        }

        return SizedBox(
          width: direction == Axis.horizontal ? spacing : null,
          height: direction == Axis.vertical ? spacing : null,
        );
      },
    );
  }
}

/// Responsive text widget that adapts font size based on screen size
class VSResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final double? mobileScale;
  final double? tabletScale;
  final double? desktopScale;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const VSResponsiveText({
    super.key,
    required this.text,
    this.baseStyle,
    this.mobileScale,
    this.tabletScale,
    this.desktopScale,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return VSResponsiveBuilder(
      builder: (context, breakpoint) {
        double scale;
        switch (breakpoint) {
          case VSBreakpoint.mobile:
            scale = mobileScale ?? 0.9;
            break;
          case VSBreakpoint.tablet:
            scale = tabletScale ?? 1.0;
            break;
          case VSBreakpoint.desktop:
          case VSBreakpoint.large:
            scale = desktopScale ?? 1.1;
            break;
        }

        final effectiveStyle = baseStyle ?? Theme.of(context).textTheme.bodyMedium;
        final scaledStyle = effectiveStyle?.copyWith(
          fontSize: (effectiveStyle.fontSize ?? 14) * scale,
        );

        return Text(
          text,
          style: scaledStyle,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}
