import 'package:flutter/material.dart';

/// Hostinger Design System Theme for MetMusic
/// Based on the hostinger-design skill specifications
class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER BRAND TOKENS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary accent — #9d99ff
  /// Used for CTAs, links, focus rings, and active states
  static const Color accent = Color(0xFF9D99FF);

  /// Background — #ffffff (light) / #000000 (dark - pure black like Hostinger)
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color darkBackground = Color(0xFF000000);

  /// Surface — #111111
  /// Cards, panels, modals, elevated surfaces
  static const Color surface = Color(0xFF111111);

  /// Page background — pure black on every page (deep black design).
  /// Light theme keeps white; dark theme uses #000000 everywhere.
  static const Color pageBackground = Color(0xFF000000);

  /// Text Primary — #f2f5fb
  /// Headings and primary text
  static const Color textPrimary = Color(0xFFF2F5FB);

  /// Text Muted — #a0a1a7
  /// Captions, placeholders, secondary info
  static const Color textMuted = Color(0xFFA0A1A7);

  /// Border — #cccccc
  static const Color border = Color(0xFFCCCCCC);

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER EXTENDED PALETTE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Brand purple — #7b66ff
  static const Color brandPurple = Color(0xFF7B66FF);

  /// Meteorite purple — #8c85ff
  static const Color meteoritePurple = Color(0xFF8C85FF);

  /// Theme violet — #673de6
  static const Color themeViolet = Color(0xFF673DE6);

  /// Blue — #4c78ff
  static const Color blue = Color(0xFF4C78FF);

  /// Sky — light blue #7ec8ff
  static const Color sky = Color(0xFF7EC8FF);

  /// Neutral 200 — #dedee2
  static const Color neutral200 = Color(0xFFDEDEE2);

  /// Neutral 500 — #797980
  static const Color neutral500 = Color(0xFF797980);

  /// Pink/Magenta — #e536db
  static const Color pink = Color(0xFFE536DB);

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color success = Color(0xFF009E5B);
  static const Color warning = Color(0xFFE69800);
  static const Color danger = Color(0xFFE73A47);

  // ═══════════════════════════════════════════════════════════════════════════
  // SURFACE VARIANTS (for layered depth)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Surface 3 (used for nested cards) — #1a1a1a
  static const Color surface3 = Color(0xFF1A1A1A);

  /// Dark elevated surface — #1c1c1c
  static const Color darkElevated = Color(0xFF1C1C1C);

  /// Light surface variants
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFF9F9FB);

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER GRADIENTS
  // ═══════════════════════════════════════════════════════════════════════════

  static const List<Color> brandGradient = [accent, meteoritePurple, brandPurple];

  static LinearGradient brandLinearGradient({
    Alignment begin = Alignment.centerLeft,
    Alignment end = Alignment.centerRight,
  }) =>
      LinearGradient(colors: brandGradient, begin: begin, end: end);

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER GLASS DECORATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Subtle glass effect (no blur per anti-pattern)
  static BoxDecoration glassDecoration({
    double radius = 22,
    double alpha = 0.08,
    double borderAlpha = 0.12,
  }) =>
      BoxDecoration(
        color: surface.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: textPrimary.withValues(alpha: borderAlpha),
        ),
      );

  /// Strong glass for modals
  static BoxDecoration glassStrongDecoration({
    double radius = 999, // Pill shape for modals
    double alpha = 0.10,
  }) =>
      BoxDecoration(
        color: surface.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1D1E20),
            blurRadius: 12,
            spreadRadius: 0,
          ),
        ],
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER TYPOGRAPHY TOKENS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Display font — DM Sans (headings)
  static const String displayFont = 'DM Sans';

  /// Body font — Noto Sans (body/UI text)
  static const String bodyFont = 'Noto Sans';

  /// Code font — SF Mono
  static const String codeFont = 'SF Mono';

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER TYPE SCALE
  // ═══════════════════════════════════════════════════════════════════════════

  static TextStyle _displayStyle({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: displayFont,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height ?? 1.2,
        letterSpacing: letterSpacing,
      );

  static TextStyle _bodyStyle({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: bodyFont,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height ?? 1.5,
        letterSpacing: letterSpacing,
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER DARK THEME
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData get darkTheme {
    const bg = darkBackground;
    const surfaceColor = surface;
    const elevatedColor = darkElevated;

    const labelPrimary = textPrimary;
    const labelSecondary = Color(0xB3F2F5FB); // 70% white
    const labelTertiary = Color(0x80F2F5FB); // 50% white
    const labelQuaternary = Color(0x4DF2F5FB); // 30% white
    const separator = Color(0x33FFFFFF); // 20% white

    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: surface,
      primaryContainer: accent.withValues(alpha: 0.2),
      onPrimaryContainer: accent,
      secondary: meteoritePurple,
      onSecondary: surface,
      secondaryContainer: meteoritePurple.withValues(alpha: 0.2),
      onSecondaryContainer: meteoritePurple,
      tertiary: brandPurple,
      onTertiary: surface,
      tertiaryContainer: brandPurple.withValues(alpha: 0.2),
      onTertiaryContainer: brandPurple,
      error: danger,
      onError: labelPrimary,
      errorContainer: danger.withValues(alpha: 0.2),
      onErrorContainer: danger,
      surface: surfaceColor,
      onSurface: labelPrimary,
      onSurfaceVariant: labelSecondary,
      outline: separator,
      outlineVariant: separator,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: lightBackground,
      onInverseSurface: surface,
      surfaceTint: accent,
      surfaceContainerLowest: bg,
      surfaceContainerLow: bg,
      surfaceContainer: surface3,
      surfaceContainerHigh: elevatedColor,
      surfaceContainerHighest: darkElevated,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _bodyStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        iconTheme: const IconThemeData(color: labelPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      iconTheme: IconThemeData(color: labelSecondary, size: 22),
      textTheme: TextTheme(
        displayLarge: _displayStyle(
          fontSize: 72,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.15,
        ),
        displayMedium: _displayStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.15,
        ),
        displaySmall: _displayStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.2,
        ),
        headlineLarge: _displayStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.2,
        ),
        headlineMedium: _displayStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.25,
        ),
        headlineSmall: _displayStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
          height: 1.3,
        ),
        titleLarge: _displayStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
          height: 1.3,
        ),
        titleMedium: _bodyStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        titleSmall: _bodyStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        bodyLarge: _bodyStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: labelPrimary,
          height: 1.5,
        ),
        bodyMedium: _bodyStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: labelSecondary,
          height: 1.5,
        ),
        bodySmall: _bodyStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: labelTertiary,
          height: 1.5,
        ),
        labelLarge: _bodyStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: accent,
        ),
        labelMedium: _bodyStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: labelTertiary,
        ),
        labelSmall: _bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: labelQuaternary,
          letterSpacing: 0.5,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: labelQuaternary,
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.15),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: surface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: _bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: surface,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: labelPrimary,
          side: BorderSide(color: separator),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: _bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: accent,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        hintStyle: _bodyStyle(fontSize: 14, color: labelTertiary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999), // Pill shape
        ),
        titleTextStyle: _displayStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        contentTextStyle: _bodyStyle(
          fontSize: 14,
          color: labelSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevatedColor,
        contentTextStyle: _bodyStyle(fontSize: 14, color: labelPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: separator,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceColor,
        selectedColor: accent.withValues(alpha: 0.2),
        labelStyle: _bodyStyle(fontSize: 12, color: labelSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999), // Pill
        ),
        side: BorderSide(color: separator),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER LIGHT THEME
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData get lightTheme {
    const bg = lightBackground;
    const surfaceColor = lightSurface;
    const elevatedColor = lightElevated;

    const labelPrimary = Color(0xFF101011);
    const labelSecondary = Color(0x99000000);
    const labelTertiary = Color(0x66000000);
    const labelQuaternary = Color(0x33000000);
    const separator = Color(0x33000000);

    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: accent,
      onPrimary: surface,
      primaryContainer: accent.withValues(alpha: 0.15),
      onPrimaryContainer: accent,
      secondary: meteoritePurple,
      onSecondary: surface,
      secondaryContainer: meteoritePurple.withValues(alpha: 0.15),
      onSecondaryContainer: meteoritePurple,
      tertiary: brandPurple,
      onTertiary: surface,
      tertiaryContainer: brandPurple.withValues(alpha: 0.15),
      onTertiaryContainer: brandPurple,
      error: danger,
      onError: labelPrimary,
      errorContainer: danger.withValues(alpha: 0.12),
      onErrorContainer: danger,
      surface: surfaceColor,
      onSurface: labelPrimary,
      onSurfaceVariant: labelSecondary,
      outline: separator,
      outlineVariant: separator,
      shadow: Colors.black12,
      scrim: Colors.black26,
      inverseSurface: surface,
      onInverseSurface: labelPrimary,
      surfaceTint: accent,
      surfaceContainerLowest: lightBackground,
      surfaceContainerLow: lightSurface,
      surfaceContainer: lightSurface,
      surfaceContainerHigh: lightElevated,
      surfaceContainerHighest: neutral200,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: _bodyStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        iconTheme: const IconThemeData(color: labelPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      iconTheme: IconThemeData(color: labelSecondary, size: 22),
      textTheme: TextTheme(
        displayLarge: _displayStyle(
          fontSize: 72,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.15,
        ),
        displayMedium: _displayStyle(
          fontSize: 40,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.15,
        ),
        displaySmall: _displayStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.2,
        ),
        headlineLarge: _displayStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.2,
        ),
        headlineMedium: _displayStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: labelPrimary,
          height: 1.25,
        ),
        headlineSmall: _displayStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
          height: 1.3,
        ),
        titleLarge: _displayStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
          height: 1.3,
        ),
        titleMedium: _bodyStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        titleSmall: _bodyStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        bodyLarge: _bodyStyle(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: labelPrimary,
          height: 1.5,
        ),
        bodyMedium: _bodyStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: labelSecondary,
          height: 1.5,
        ),
        bodySmall: _bodyStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: labelTertiary,
          height: 1.5,
        ),
        labelLarge: _bodyStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: accent,
        ),
        labelMedium: _bodyStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: labelTertiary,
        ),
        labelSmall: _bodyStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: labelQuaternary,
          letterSpacing: 0.5,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: labelQuaternary,
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.15),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: surface,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          textStyle: _bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: surface,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: labelPrimary,
          side: BorderSide(color: separator),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: _bodyStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: accent,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: separator),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: accent, width: 2),
        ),
        hintStyle: _bodyStyle(fontSize: 14, color: labelTertiary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999), // Pill shape
        ),
        titleTextStyle: _displayStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: labelPrimary,
        ),
        contentTextStyle: _bodyStyle(
          fontSize: 14,
          color: labelSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: elevatedColor,
        contentTextStyle: _bodyStyle(fontSize: 14, color: labelPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(22),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: separator,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceColor,
        selectedColor: accent.withValues(alpha: 0.15),
        labelStyle: _bodyStyle(fontSize: 12, color: labelSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999), // Pill
        ),
        side: BorderSide(color: separator),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER SPACING TOKENS (4px Grid)
  // ═══════════════════════════════════════════════════════════════════════════

  /// 4px — Tight spacing
  static const double space1 = 4.0;
  /// 8px — Medium spacing
  static const double space2 = 8.0;
  /// 12px — Related items
  static const double space3 = 12.0;
  /// 16px — Between groups
  static const double space4 = 16.0;
  /// 20px
  static const double space5 = 20.0;
  /// 24px — Between sections
  static const double space6 = 24.0;
  /// 32px — Wide spacing
  static const double space7 = 32.0;
  /// 40px
  static const double space8 = 40.0;
  /// 48px — Vast spacing (major breaks)
  static const double space9 = 48.0;
  /// 64px
  static const double space10 = 64.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER BORDER RADIUS TOKENS
  // ═══════════════════════════════════════════════════════════════════════════

  /// 2px — Subtle
  static const double radiusXs = 2.0;
  /// 4px
  static const double radiusSm = 4.0;
  /// 6px
  static const double radiusMd = 6.0;
  /// 8px
  static const double radiusLg = 8.0;
  /// 10px
  static const double radiusXl = 10.0;
  /// 12px
  static const double radius2xl = 12.0;
  /// 16px
  static const double radius3xl = 16.0;
  /// 20px
  static const double radius4xl = 20.0;
  /// 22px — Default radius
  static const double radiusDefault = 22.0;
  /// 24px
  static const double radius5xl = 24.0;
  /// 999px — Pill shape
  static const double radiusPill = 999.0;

  /// Max content width
  static const double maxContentWidth = 1600.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER SHADOW TOKENS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Subtle elevation
  static List<BoxShadow> get shadowSubtle => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// Medium elevation (cards)
  static List<BoxShadow> get shadowMedium => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  /// Strong elevation (modals, floating)
  static List<BoxShadow> get shadowStrong => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  /// Accent glow
  static List<BoxShadow> accentGlow(double strength) => [
        BoxShadow(
          color: accent.withValues(alpha: 0.35 * strength),
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ];

  /// Tinted glow shadow (see [accentGlow] for the fixed accent variant).
  static List<BoxShadow> glowShadow(Color color, double strength) => [
        BoxShadow(
          color: color.withValues(alpha: 0.35 * strength),
          blurRadius: 24,
          spreadRadius: 0,
        ),
      ];

  // ═══════════════════════════════════════════════════════════════════════════
  // HOSTINGER COMPONENT HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Standard card decoration
  static BoxDecoration cardDecoration({
    Color? backgroundColor,
    double radius = 22,
  }) =>
      BoxDecoration(
        color: backgroundColor ?? surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadowMedium,
      );

  /// Hostinger button styles
  static ButtonStyle primaryButtonStyle(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: surface,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }

  static ButtonStyle ghostButtonStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      foregroundColor: textPrimary,
      side: BorderSide(color: border.withValues(alpha: 0.3)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    );
  }

  /// Hostinger badge/chip
  static BoxDecoration badgeDecoration({
    Color? backgroundColor,
    Color? textColor,
  }) =>
      BoxDecoration(
        color: backgroundColor ?? surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: border.withValues(alpha: 0.2),
        ),
      );
}
