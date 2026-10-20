import 'package:flutter/material.dart';

/// Aura by HS palette — the same tokens as the POS and the website:
/// bridal maroon, antique gold and a warm ivory canvas. Light theme only.
class AppColors {
  static const Color maroon = Color(0xFF7A181C);
  static const Color maroonDeep = Color(0xFF4A0E12);
  static const Color maroonInk = Color(0xFF2B0709);
  static const Color gold = Color(0xFFC9A45C);
  static const Color goldLight = Color(0xFFE6C98A);
  static const Color goldSoft = Color(0xFFF6EBD3);
  static const Color ivory = Color(0xFFFBF7F2);
  static const Color background = ivory;
  static const Color card = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF1F1A17);
  static const Color muted = Color(0xFFF3ECE4);
  static const Color mutedForeground = Color(0xFF7B6D66);
  static const Color border = Color(0xFFEAE0D6);
  static const Color secondary = Color(0xFFF5EDE3);
  static const Color success = Color(0xFF2E8B57);
  static const Color successSoft = Color(0xFFE3F4EA);
  static const Color warning = Color(0xFFD4952B);
  static const Color destructive = Color(0xFFC62E3A);
  static const Color destructiveSoft = Color(0xFFFBE7E8);
  static const Color jazzcash = Color(0xFFC8102E);
  static const Color easypaisa = Color(0xFF00A651);
  static const Color visa = Color(0xFF1A1F71);
}

class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double xxl = 30;
}

class AppShadows {
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3), spreadRadius: -2),
  ];
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x267A181C), blurRadius: 30, offset: Offset(0, 14), spreadRadius: -14),
  ];
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x557A181C), blurRadius: 40, offset: Offset(0, 18), spreadRadius: -16),
  ];
}

class AppGradients {
  static const LinearGradient maroon = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7A181C), Color(0xFF9A3326)],
  );
  static const LinearGradient gold = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFFE6C98A), Color(0xFFC9A45C)],
  );
  static const RadialGradient splash = RadialGradient(
    radius: 1.1,
    colors: [Color(0xFF6E1B1F), Color(0xFF3E0C10), Color(0xFF240607)],
    stops: [0, 0.6, 1],
  );
}

/// Fraunces for headings (as on the website), Inter for everything else.
class AppText {
  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.foreground,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) =>
      TextStyle(
        fontFamily: 'Inter',
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );

  static TextStyle display({
    double size = 20,
    FontWeight weight = FontWeight.w600,
    Color color = AppColors.foreground,
    double? height,
    FontStyle style = FontStyle.normal,
  }) =>
      TextStyle(
        fontFamily: 'Fraunces',
        fontVariations: [FontVariation('wght', weight.value.toDouble())],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        fontStyle: style,
        letterSpacing: -0.01 * size,
      );

  /// Small uppercase gold eyebrow, e.g. "BRIDAL MAKE-UP".
  static TextStyle eyebrow({Color color = AppColors.gold, double size = 10.5}) =>
      sans(size: size, weight: FontWeight.w600, color: color, letterSpacing: size * 0.28);
}

ThemeData buildAuraTheme() {
  final base = ThemeData(useMaterial3: true, brightness: Brightness.light, fontFamily: 'Inter');
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.light(
      primary: AppColors.maroon,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      onSecondary: AppColors.maroon,
      surface: AppColors.card,
      onSurface: AppColors.foreground,
      error: AppColors.destructive,
      outline: AppColors.border,
    ),

    splashFactory: InkRipple.splashFactory,
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    dividerColor: AppColors.border,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.maroonInk,
      contentTextStyle: AppText.sans(size: 13, color: Colors.white, weight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: AppText.sans(size: 14, color: AppColors.mutedForeground),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.4),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.maroon : null),
    ),
  );
}
