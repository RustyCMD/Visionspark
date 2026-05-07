import 'package:flutter/material.dart';

/// VisionSpark — Aurora design tokens.
///
/// One palette, one spacing scale, one radius scale. Every screen reaches
/// through this file so a single edit re-tones the whole app.
class VSDesignTokens {
  VSDesignTokens._();

  // Spacing — 4px grid.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;
  static const double space20 = 80;

  // Radii — generous, modern.
  static const double radiusXS = 6;
  static const double radiusS = 10;
  static const double radiusM = 14;
  static const double radiusL = 18;
  static const double radiusXL = 24;
  static const double radiusXXL = 28;
  static const double radiusRound = 999;

  // Elevation.
  static const double elevation0 = 0;
  static const double elevation1 = 1;
  static const double elevation2 = 3;
  static const double elevation4 = 6;
  static const double elevation6 = 10;
  static const double elevation8 = 16;
  static const double elevation12 = 24;
  static const double elevation16 = 32;
  static const double elevation24 = 48;

  // Motion.
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 280);
  static const Duration durationSlow = Duration(milliseconds: 420);
  static const Duration durationXSlow = Duration(milliseconds: 700);

  // Touch targets.
  static const double touchTargetMin = 48;
  static const double touchTargetComfortable = 56;
  static const double touchTargetLarge = 64;

  // Icon sizes.
  static const double iconXS = 16;
  static const double iconS = 20;
  static const double iconM = 24;
  static const double iconL = 32;
  static const double iconXL = 48;
  static const double iconXXL = 64;

  // Layout breakpoints.
  static const double breakpointMobile = 480;
  static const double breakpointTablet = 768;
  static const double breakpointDesktop = 1024;
  static const double breakpointLarge = 1440;

  // Content max widths.
  static const double maxWidthMobile = 480;
  static const double maxWidthTablet = 768;
  static const double maxWidthDesktop = 1200;
  static const double maxWidthContent = 800;

  // Opacity.
  static const double opacityDisabled = 0.38;
  static const double opacityMedium = 0.6;
  static const double opacityHigh = 0.87;
  static const double opacityFull = 1;
}

/// Aurora Violet + Cyan palette.
///
/// Primary is violet (#7C5CFF), accent is cyan (#22D3EE), backed by a
/// near-black surface in dark mode and clean off-white in light mode.
class VSColors {
  VSColors._();

  // Brand.
  static const Color violet         = Color(0xFF7C5CFF);
  static const Color violetSoft     = Color(0xFF9B85FF);
  static const Color violetDeep     = Color(0xFF5B3FE0);
  static const Color cyan           = Color(0xFF22D3EE);
  static const Color cyanSoft       = Color(0xFF5BE3F2);
  static const Color cyanDeep       = Color(0xFF0BB4CC);

  // Dark surfaces.
  static const Color ink            = Color(0xFF0B0B12);
  static const Color surfaceDark    = Color(0xFF12121C);
  static const Color surfaceDark2   = Color(0xFF1A1A28);
  static const Color surfaceDark3   = Color(0xFF222234);
  static const Color outlineDark    = Color(0xFF34344A);

  // Light surfaces.
  static const Color paper          = Color(0xFFFAFAFC);
  static const Color surfaceLight   = Color(0xFFFFFFFF);
  static const Color surfaceLight2  = Color(0xFFF1F1F6);
  static const Color surfaceLight3  = Color(0xFFE6E6EE);
  static const Color outlineLight   = Color(0xFFD4D4DE);

  // Foreground.
  static const Color textOnDark     = Color(0xFFF4F4F8);
  static const Color textOnDarkDim  = Color(0xFFB4B4C2);
  static const Color textOnLight    = Color(0xFF0B0B12);
  static const Color textOnLightDim = Color(0xFF55556A);

  // Semantic.
  static const Color success        = Color(0xFF22C55E);
  static const Color warning        = Color(0xFFF59E0B);
  static const Color info           = Color(0xFF38BDF8);
  static const Color danger         = Color(0xFFEF4444);

  // Legacy alpha helpers retained for compatibility.
  static const Color black12 = Color(0x1F000000);
  static const Color black26 = Color(0x42000000);
  static const Color black38 = Color(0x61000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black87 = Color(0xDD000000);
  static const Color white12 = Color(0x1FFFFFFF);
  static const Color white24 = Color(0x3DFFFFFF);
  static const Color white38 = Color(0x61FFFFFF);
  static const Color white54 = Color(0x8AFFFFFF);
  static const Color white70 = Color(0xB3FFFFFF);
  static const Color white87 = Color(0xDDFFFFFF);

  // Legacy gray ramp (kept so older callers compile).
  static const Color gray50  = Color(0xFFFAFAFA);
  static const Color gray100 = Color(0xFFF5F5F5);
  static const Color gray200 = Color(0xFFEEEEEE);
  static const Color gray300 = Color(0xFFE0E0E0);
  static const Color gray400 = Color(0xFFBDBDBD);
  static const Color gray500 = Color(0xFF9E9E9E);
  static const Color gray600 = Color(0xFF757575);
  static const Color gray700 = Color(0xFF616161);
  static const Color gray800 = Color(0xFF424242);
  static const Color gray900 = Color(0xFF212121);
}

/// Typography scale.
class VSTypography {
  VSTypography._();

  static const FontWeight weightLight     = FontWeight.w300;
  static const FontWeight weightRegular   = FontWeight.w400;
  static const FontWeight weightMedium    = FontWeight.w500;
  static const FontWeight weightSemiBold  = FontWeight.w600;
  static const FontWeight weightBold      = FontWeight.w700;
  static const FontWeight weightExtraBold = FontWeight.w800;

  static const double fontSize10 = 10;
  static const double fontSize12 = 12;
  static const double fontSize14 = 14;
  static const double fontSize16 = 16;
  static const double fontSize18 = 18;
  static const double fontSize20 = 20;
  static const double fontSize24 = 24;
  static const double fontSize28 = 28;
  static const double fontSize32 = 32;
  static const double fontSize36 = 36;
  static const double fontSize48 = 48;
  static const double fontSize64 = 64;

  static const double lineHeightTight   = 1.2;
  static const double lineHeightNormal  = 1.4;
  static const double lineHeightRelaxed = 1.6;

  static const double letterSpacingTight  = -0.5;
  static const double letterSpacingNormal = 0;
  static const double letterSpacingWide   = 0.4;
}

/// Pre-built ColorSchemes for the app.
class VSColorSchemes {
  VSColorSchemes._();

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: VSColors.violet,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF2A1F66),
    onPrimaryContainer: Color(0xFFE2D9FF),
    secondary: VSColors.cyan,
    onSecondary: VSColors.ink,
    secondaryContainer: Color(0xFF0F4A55),
    onSecondaryContainer: Color(0xFFC1F4FB),
    tertiary: Color(0xFFFF7AB8),
    onTertiary: VSColors.ink,
    tertiaryContainer: Color(0xFF5A1A3F),
    onTertiaryContainer: Color(0xFFFFD7EA),
    error: VSColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFF601313),
    onErrorContainer: Color(0xFFFFD9D9),
    surface: VSColors.surfaceDark,
    onSurface: VSColors.textOnDark,
    onSurfaceVariant: VSColors.textOnDarkDim,
    surfaceContainerLowest: VSColors.ink,
    surfaceContainerLow: Color(0xFF15151F),
    surfaceContainer: VSColors.surfaceDark2,
    surfaceContainerHigh: Color(0xFF1F1F2E),
    surfaceContainerHighest: VSColors.surfaceDark3,
    outline: VSColors.outlineDark,
    outlineVariant: Color(0xFF26263A),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: VSColors.paper,
    onInverseSurface: VSColors.ink,
    inversePrimary: VSColors.violetDeep,
    surfaceTint: VSColors.violet,
  );

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: VSColors.violetDeep,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE6DEFF),
    onPrimaryContainer: Color(0xFF1F1148),
    secondary: VSColors.cyanDeep,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFCBF3F9),
    onSecondaryContainer: Color(0xFF003B43),
    tertiary: Color(0xFFC03A82),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFFFD7EA),
    onTertiaryContainer: Color(0xFF3F0027),
    error: Color(0xFFD32F2F),
    onError: Colors.white,
    errorContainer: Color(0xFFFFD9D9),
    onErrorContainer: Color(0xFF410002),
    surface: VSColors.surfaceLight,
    onSurface: VSColors.textOnLight,
    onSurfaceVariant: VSColors.textOnLightDim,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: VSColors.paper,
    surfaceContainer: VSColors.surfaceLight2,
    surfaceContainerHigh: Color(0xFFEBEBF1),
    surfaceContainerHighest: VSColors.surfaceLight3,
    outline: VSColors.outlineLight,
    outlineVariant: Color(0xFFE9E9F1),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: VSColors.surfaceDark,
    onInverseSurface: VSColors.textOnDark,
    inversePrimary: VSColors.violetSoft,
    surfaceTint: VSColors.violetDeep,
  );
}
