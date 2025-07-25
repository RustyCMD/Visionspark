import 'package:flutter/material.dart';

/// VisionSpark Design System - Design Tokens
/// 
/// This file contains all the design tokens used throughout the VisionSpark app
/// to ensure consistency in spacing, typography, colors, and other design elements.

class VSDesignTokens {
  VSDesignTokens._();

  // ============================================================================
  // SPACING SYSTEM
  // ============================================================================
  
  /// Base spacing unit (4px) - all spacing should be multiples of this
  static const double spaceUnit = 4.0;
  
  /// Spacing scale based on 4px grid system
  static const double space1 = spaceUnit * 1;      // 4px
  static const double space2 = spaceUnit * 2;      // 8px
  static const double space3 = spaceUnit * 3;      // 12px
  static const double space4 = spaceUnit * 4;      // 16px
  static const double space5 = spaceUnit * 5;      // 20px
  static const double space6 = spaceUnit * 6;      // 24px
  static const double space8 = spaceUnit * 8;      // 32px
  static const double space10 = spaceUnit * 10;    // 40px
  static const double space12 = spaceUnit * 12;    // 48px
  static const double space16 = spaceUnit * 16;    // 64px
  static const double space20 = spaceUnit * 20;    // 80px
  
  // ============================================================================
  // BORDER RADIUS SYSTEM
  // ============================================================================
  
  static const double radiusXS = 4.0;
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 20.0;
  static const double radiusXXL = 24.0;
  static const double radiusRound = 999.0;
  
  // ============================================================================
  // ELEVATION SYSTEM
  // ============================================================================
  
  static const double elevation0 = 0.0;
  static const double elevation1 = 1.0;
  static const double elevation2 = 2.0;
  static const double elevation4 = 4.0;
  static const double elevation6 = 6.0;
  static const double elevation8 = 8.0;
  static const double elevation12 = 12.0;
  static const double elevation16 = 16.0;
  static const double elevation24 = 24.0;
  
  // ============================================================================
  // ANIMATION DURATIONS
  // ============================================================================
  
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 300);
  static const Duration durationSlow = Duration(milliseconds: 500);
  static const Duration durationXSlow = Duration(milliseconds: 800);
  
  // ============================================================================
  // OPACITY VALUES
  // ============================================================================
  
  static const double opacityDisabled = 0.38;
  static const double opacityMedium = 0.6;
  static const double opacityHigh = 0.87;
  static const double opacityFull = 1.0;
  
  // ============================================================================
  // TOUCH TARGET SIZES (Accessibility)
  // ============================================================================
  
  static const double touchTargetMin = 48.0;
  static const double touchTargetComfortable = 56.0;
  static const double touchTargetLarge = 64.0;
  
  // ============================================================================
  // ICON SIZES
  // ============================================================================
  
  static const double iconXS = 16.0;
  static const double iconS = 20.0;
  static const double iconM = 24.0;
  static const double iconL = 32.0;
  static const double iconXL = 48.0;
  static const double iconXXL = 64.0;
  
  // ============================================================================
  // LAYOUT BREAKPOINTS
  // ============================================================================
  
  static const double breakpointMobile = 480.0;
  static const double breakpointTablet = 768.0;
  static const double breakpointDesktop = 1024.0;
  static const double breakpointLarge = 1440.0;
  
  // ============================================================================
  // CONTENT MAX WIDTHS
  // ============================================================================
  
  static const double maxWidthMobile = 480.0;
  static const double maxWidthTablet = 768.0;
  static const double maxWidthDesktop = 1200.0;
  static const double maxWidthContent = 800.0;
  
  // ============================================================================
  // GRID SYSTEM
  // ============================================================================
  
  static const int gridColumns = 12;
  static const double gridGutter = space4;
  static const double gridMargin = space4;
  
  // ============================================================================
  // Z-INDEX LAYERS
  // ============================================================================
  
  static const int zIndexBase = 0;
  static const int zIndexDropdown = 1000;
  static const int zIndexSticky = 1020;
  static const int zIndexFixed = 1030;
  static const int zIndexModalBackdrop = 1040;
  static const int zIndexModal = 1050;
  static const int zIndexPopover = 1060;
  static const int zIndexTooltip = 1070;
  static const int zIndexToast = 1080;
}

/// VisionSpark Color Palette Extensions
/// 
/// Extended color palette beyond Material Design 3 base colors
class VSColors {
  VSColors._();
  
  // ============================================================================
  // BRAND COLORS
  // ============================================================================
  
  static const Color primaryIndigo = Color(0xFF3949AB);
  static const Color secondaryTeal = Color(0xFF00ACC1);
  static const Color accentAmber = Color(0xFFFFB300);
  
  // ============================================================================
  // SEMANTIC COLORS
  // ============================================================================
  
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);
  
  // ============================================================================
  // NEUTRAL GRAYS
  // ============================================================================
  
  static const Color gray50 = Color(0xFFFAFAFA);
  static const Color gray100 = Color(0xFFF5F5F5);
  static const Color gray200 = Color(0xFFEEEEEE);
  static const Color gray300 = Color(0xFFE0E0E0);
  static const Color gray400 = Color(0xFFBDBDBD);
  static const Color gray500 = Color(0xFF9E9E9E);
  static const Color gray600 = Color(0xFF757575);
  static const Color gray700 = Color(0xFF616161);
  static const Color gray800 = Color(0xFF424242);
  static const Color gray900 = Color(0xFF212121);
  
  // ============================================================================
  // ALPHA COLORS (for overlays, shadows, etc.)
  // ============================================================================
  
  static Color black12 = Colors.black.withOpacity(0.12);
  static Color black26 = Colors.black.withOpacity(0.26);
  static Color black38 = Colors.black.withOpacity(0.38);
  static Color black54 = Colors.black.withOpacity(0.54);
  static Color black87 = Colors.black.withOpacity(0.87);
  
  static Color white12 = Colors.white.withOpacity(0.12);
  static Color white24 = Colors.white.withOpacity(0.24);
  static Color white38 = Colors.white.withOpacity(0.38);
  static Color white54 = Colors.white.withOpacity(0.54);
  static Color white70 = Colors.white.withOpacity(0.70);
  static Color white87 = Colors.white.withOpacity(0.87);
}

/// Typography Scale Extensions
/// 
/// Extended typography system with consistent font weights and sizes
class VSTypography {
  VSTypography._();
  
  // ============================================================================
  // FONT WEIGHTS
  // ============================================================================
  
  static const FontWeight weightLight = FontWeight.w300;
  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemiBold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightExtraBold = FontWeight.w800;
  
  // ============================================================================
  // FONT SIZES
  // ============================================================================
  
  static const double fontSize10 = 10.0;
  static const double fontSize12 = 12.0;
  static const double fontSize14 = 14.0;
  static const double fontSize16 = 16.0;
  static const double fontSize18 = 18.0;
  static const double fontSize20 = 20.0;
  static const double fontSize24 = 24.0;
  static const double fontSize28 = 28.0;
  static const double fontSize32 = 32.0;
  static const double fontSize36 = 36.0;
  static const double fontSize48 = 48.0;
  static const double fontSize64 = 64.0;
  
  // ============================================================================
  // LINE HEIGHTS
  // ============================================================================
  
  static const double lineHeightTight = 1.2;
  static const double lineHeightNormal = 1.4;
  static const double lineHeightRelaxed = 1.6;
  static const double lineHeightLoose = 1.8;
  
  // ============================================================================
  // LETTER SPACING
  // ============================================================================
  
  static const double letterSpacingTight = -0.5;
  static const double letterSpacingNormal = 0.0;
  static const double letterSpacingWide = 0.5;
  static const double letterSpacingWider = 1.0;
}
