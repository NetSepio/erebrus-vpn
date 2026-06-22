import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Erebrus design language — the "agentic internet" dark system.
///
/// Deep near-black canvas, flat elevated surfaces with hairline strokes, a vivid
/// brand orange accent (#ff6b35), Space Grotesk for display/UI and IBM Plex Mono
/// for labels/data. Every screen pulls tokens from here rather than hard-coding.
///
/// Legacy token names (indigo/cyan/violet/connected/connecting/stealth/surfaceHi)
/// are preserved but repointed onto the new palette so older screens stay on
/// brand without edits.
class AppColors {
  AppColors._();

  // canvas & surfaces
  static const Color bg = Color(0xFF0A0A0C);
  static const Color bgDeep = Color(0xFF050507);
  static const Color bgElevated = Color(0xFF0D0D11);
  static const Color raised = Color(0xFF0E0E12);
  static const Color surface = Color(0xFF131318);
  static const Color surface2 = Color(0xFF16161B);
  static const Color surface3 = Color(0xFF1D1D23);
  static const Color surfaceHi = surface3; // legacy alias

  /// Hairline border — white @ ~8%.
  static const Color stroke = Color(0x14FFFFFF);
  static const Color strokeSoft = Color(0x0FFFFFFF); // ~6%
  static const Color strokeHi = Color(0x1FFFFFFF); // ~12%

  // text
  static const Color textPrimary = Color(0xFFF4F3F0);
  static const Color textSecondary = Color(0xFF9A9AA2);
  static const Color textTertiary = Color(0xFF8A8A93);
  static const Color textMuted = Color(0xFF6A6A72);
  static const Color textDim = Color(0xFF5C5C64);

  // brand accent
  static const Color accent = Color(0xFFFF6B35);
  static const Color accentHi = Color(0xFFFF7E44);
  static const Color accentDeep = Color(0xFFE0531F);
  static const Color onAccent = Color(0xFF0A0A0C);

  // semantic
  static const Color success = Color(0xFF36D399); // protected / secure
  static const Color warn = Color(0xFFE6A13C);
  static const Color danger = Color(0xFFE35D5D);

  // chains / network
  static const Color solana = Color(0xFF9945FF);
  static const Color solanaAlt = Color(0xFF14F195);
  static const Color ethereum = Color(0xFF627EEA);
  static const Color shared = Color(0xFF3AA0FF);

  // ---- legacy aliases (repointed onto the brand palette) ----
  static const Color indigo = accent;
  static const Color violet = solana;
  static const Color cyan = accentHi;
  static const Color connected = success;
  static const Color connecting = warn;
  static const Color stealth = solana;
}

class AppGradients {
  AppGradients._();

  /// Primary brand fill (formerly "aurora").
  static const LinearGradient aurora = LinearGradient(
    begin: Alignment(-0.7, -1),
    end: Alignment(0.7, 1),
    colors: [AppColors.accentHi, AppColors.accentDeep],
  );

  /// Square brand logo lockup fill.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment(0.0, -1),
    end: Alignment(0.4, 1),
    colors: [Color(0xFFFF7E44), Color(0xFFE0531F)],
  );

  /// Stealth carriers use violet→orange.
  static const LinearGradient stealth = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.solana, AppColors.accent],
  );

  /// Solana chip gradient.
  static const LinearGradient solana = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.solana, AppColors.solanaAlt],
  );

  /// Ethereum chip gradient.
  static const LinearGradient ethereum = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.ethereum, Color(0xFF3A4A8C)],
  );

  /// Connected state warms orange.
  static const LinearGradient protected = aurora;

  /// Subtle top-down sheen for glass cards.
  static LinearGradient glass = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.015)],
  );

  /// Onboarding / dark screen background radial.
  static const RadialGradient onbBackdrop = RadialGradient(
    center: Alignment(0, -0.84),
    radius: 1.1,
    colors: [Color(0xFF1C1208), AppColors.bg],
    stops: [0.0, 0.55],
  );
}

/// Spacing scale.
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
  static const double md = 14;
  static const double lg = 16;
  static const double card = 16;
  static const double pill = 999;
  static const double sheet = 26;
}

/// Font families.
class AppFonts {
  AppFonts._();
  static const String display = 'Space Grotesk';
  static const String mono = 'IBM Plex Mono';
}

/// IBM Plex Mono text — for labels, codes, metrics, and tracked captions.
TextStyle mono({
  double size = 12,
  FontWeight weight = FontWeight.w500,
  Color color = AppColors.textSecondary,
  double letterSpacing = 0.05,
  double? height,
}) =>
    TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

/// Space Grotesk display/UI text.
TextStyle grotesk({
  double size = 15,
  FontWeight weight = FontWeight.w600,
  Color color = AppColors.textPrimary,
  double letterSpacing = 0,
  double? height,
}) =>
    TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accentHi,
      surface: AppColors.surface,
      error: AppColors.danger,
      onPrimary: AppColors.onAccent,
      onSurface: AppColors.textPrimary,
    );

    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = _textTheme(base.textTheme);
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      canvasColor: AppColors.bg,
      // Prevents Material ink from calling findRenderObject on deactivated
      // scrollables during tab/route transitions (inactive element crash).
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: AppColors.stroke,
      cardColor: AppColors.surface,
    );
  }

  static TextTheme _textTheme(TextTheme b) {
    TextStyle s(double size, FontWeight w,
            {double ls = 0, Color c = AppColors.textPrimary, double h = 1.25}) =>
        TextStyle(
            fontFamily: AppFonts.display,
            fontSize: size,
            fontWeight: w,
            letterSpacing: ls,
            color: c,
            height: h);
    return b.copyWith(
      displayLarge: s(38, FontWeight.w600, ls: -0.8, h: 1.08),
      displaySmall: s(31, FontWeight.w600, ls: -0.6, h: 1.12),
      headlineSmall: s(24, FontWeight.w600, ls: -0.4),
      titleLarge: s(18, FontWeight.w600, ls: -0.2),
      titleMedium: s(15, FontWeight.w600),
      bodyLarge: s(15.5, FontWeight.w400, c: AppColors.textSecondary, h: 1.55),
      bodyMedium: s(13.5, FontWeight.w400, c: AppColors.textSecondary, h: 1.45),
      labelLarge: s(14, FontWeight.w600, ls: 0.2),
      labelSmall: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.4,
          color: AppColors.textMuted),
    );
  }
}
