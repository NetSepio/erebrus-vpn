import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Erebrus v2 design language — a premium "stealth aurora" dark theme.
///
/// Goal: not just another VPN app. Deep near-black canvas, softly elevated
/// glass surfaces, and a vivid indigo→cyan aurora accent, with a distinct mint
/// for the "protected" state. All screens should pull tokens from here rather
/// than hard-coding colors.

class AppColors {
  AppColors._();

  // canvas & surfaces
  static const Color bg = Color(0xFF0A0B0F);
  static const Color bgElevated = Color(0xFF111319);
  static const Color surface = Color(0xFF161922);
  static const Color surfaceHi = Color(0xFF1E2230);
  static const Color stroke = Color(0xFF262B3A);

  // text
  static const Color textPrimary = Color(0xFFF4F6FB);
  static const Color textSecondary = Color(0xFFA6AEC2);
  static const Color textMuted = Color(0xFF6B7488);

  // brand aurora
  static const Color indigo = Color(0xFF6D5DFB);
  static const Color violet = Color(0xFF9B6DFF);
  static const Color cyan = Color(0xFF00D4FF);

  // semantic
  static const Color connected = Color(0xFF00E5A0); // mint = protected
  static const Color connecting = Color(0xFFFFC453); // amber
  static const Color danger = Color(0xFFFF5C7A);
  static const Color stealth = Color(0xFF9B6DFF); // stealth carriers use violet
}

class AppGradients {
  AppGradients._();

  static const LinearGradient aurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.indigo, AppColors.cyan],
  );

  static const LinearGradient stealth = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.violet, AppColors.indigo],
  );

  static const LinearGradient protected = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.connected, AppColors.cyan],
  );

  /// Subtle top-down sheen for glass cards.
  static LinearGradient glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.02)],
  );
}

/// Spacing scale (4pt grid).
class AppSpace {
  AppSpace._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;
}

class AppTheme {
  AppTheme._();

  static const String _fontFamily = 'Roboto'; // swap for a brand face later

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.indigo,
      secondary: AppColors.cyan,
      surface: AppColors.surface,
      error: AppColors.danger,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    );

    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      splashColor: AppColors.indigo.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: _textTheme(base.textTheme),
      dividerColor: AppColors.stroke,
      cardColor: AppColors.surface,
    );
  }

  static TextTheme _textTheme(TextTheme b) {
    TextStyle s(double size, FontWeight w, {double ls = 0, Color c = AppColors.textPrimary, double h = 1.25}) =>
        TextStyle(fontFamily: _fontFamily, fontSize: size, fontWeight: w, letterSpacing: ls, color: c, height: h);
    return b.copyWith(
      displayLarge: s(40, FontWeight.w800, ls: -1),
      displaySmall: s(30, FontWeight.w800, ls: -0.6),
      headlineSmall: s(22, FontWeight.w700, ls: -0.3),
      titleLarge: s(18, FontWeight.w700, ls: -0.2),
      titleMedium: s(15, FontWeight.w600),
      bodyLarge: s(15, FontWeight.w500, c: AppColors.textSecondary, h: 1.4),
      bodyMedium: s(13.5, FontWeight.w500, c: AppColors.textSecondary, h: 1.4),
      labelLarge: s(14, FontWeight.w700, ls: 0.2),
      labelSmall: s(11, FontWeight.w700, ls: 1.2, c: AppColors.textMuted),
    );
  }
}
