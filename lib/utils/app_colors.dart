import 'package:flutter/material.dart';

/// SafeStep's palette - adaptive to the device's system light/dark setting.
///
/// These used to be compile-time constants. They are now plain static fields,
/// reassigned in place by [applyBrightness] whenever the OS reports a change.
/// Every screen still writes `AppColors.primary` exactly as before; nothing
/// that reads a color needed to change; only the handful of `const` widgets
/// that baked a color in at compile time had to drop that `const` so they
/// re-read the field on every rebuild instead of freezing its first value.
class AppColors {
  const AppColors._();

  static Brightness _brightness = Brightness.light;

  static Brightness get brightness => _brightness;

  // Brand
  static Color primary = _Light.primary;
  static Color primaryDark = _Light.primaryDark;
  static Color primarySoft = _Light.primarySoft;
  static Color accent = _Light.accent;

  // Surfaces
  static Color background = _Light.background;
  static Color surface = _Light.surface;
  static Color surfaceVariant = _Light.surfaceVariant;
  static Color surfaceSunken = _Light.surfaceSunken;

  // Lines
  static Color border = _Light.border;
  static Color borderStrong = _Light.borderStrong;

  // Text
  static Color textPrimary = _Light.textPrimary;
  static Color textSecondary = _Light.textSecondary;
  static Color textTertiary = _Light.textTertiary;

  // Status
  static Color success = _Light.success;
  static Color warning = _Light.warning;
  static Color danger = _Light.danger;

  static Color shadow = _Light.shadow;

  /// A surface that stays dark in both modes, for chrome that always wants
  /// light text on it - a snackbar or a tooltip. [textPrimary] cannot serve
  /// that job itself: it has to flip to a light color in dark mode for body
  /// text to stay readable, which would turn a snackbar that keyed off it
  /// into a light chip with invisible white text.
  static Color inverseSurface = _Light.inverseSurface;

  /// Updates every field above to match [newBrightness]. A no-op when the
  /// app is already in that mode, so a caller can call this on every frame
  /// callback without forcing redundant rebuilds.
  static bool applyBrightness(Brightness newBrightness) {
    if (_brightness == newBrightness) return false;
    _brightness = newBrightness;

    final palette = newBrightness == Brightness.dark ? _Dark.map : _Light.map;

    primary = palette['primary']!;
    primaryDark = palette['primaryDark']!;
    primarySoft = palette['primarySoft']!;
    accent = palette['accent']!;
    background = palette['background']!;
    surface = palette['surface']!;
    surfaceVariant = palette['surfaceVariant']!;
    surfaceSunken = palette['surfaceSunken']!;
    border = palette['border']!;
    borderStrong = palette['borderStrong']!;
    textPrimary = palette['textPrimary']!;
    textSecondary = palette['textSecondary']!;
    textTertiary = palette['textTertiary']!;
    success = palette['success']!;
    warning = palette['warning']!;
    danger = palette['danger']!;
    shadow = palette['shadow']!;
    inverseSurface = palette['inverseSurface']!;

    return true;
  }
}

class _Light {
  const _Light._();

  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primarySoft = Color(0xFF60A5FA);
  static const Color accent = Color(0xFF93C5FD);

  static const Color background = Color(0xFFF6FAFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEAF4FF);
  static const Color surfaceSunken = Color(0xFFF1F7FE);

  static const Color border = Color(0xFFDDEBFA);
  static const Color borderStrong = Color(0xFFC3DBF4);

  static const Color textPrimary = Color(0xFF10304A);
  static const Color textSecondary = Color(0xFF5D738B);
  static const Color textTertiary = Color(0xFF8CA0B6);

  static const Color success = Color(0xFF0FA97D);
  static const Color warning = Color(0xFFB86E00);
  static const Color danger = Color(0xFFD14343);

  static const Color shadow = Color(0xFFB7D8F8);
  static const Color inverseSurface = Color(0xFF10304A);

  static const Map<String, Color> map = {
    'primary': primary,
    'primaryDark': primaryDark,
    'primarySoft': primarySoft,
    'accent': accent,
    'background': background,
    'surface': surface,
    'surfaceVariant': surfaceVariant,
    'surfaceSunken': surfaceSunken,
    'border': border,
    'borderStrong': borderStrong,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'textTertiary': textTertiary,
    'success': success,
    'warning': warning,
    'danger': danger,
    'shadow': shadow,
    'inverseSurface': inverseSurface,
  };
}

/// Mirrors [_Light] one token at a time rather than inverting it
/// mechanically: a dark theme that just flips lightness tends to leave
/// over-saturated brand colors that glare against a dark surface, so primary,
/// success, warning and danger are each pulled back a step from their light
/// values.
class _Dark {
  const _Dark._();

  static const Color primary = Color(0xFF5B8DEF);
  static const Color primaryDark = Color(0xFF3B6FDB);
  static const Color primarySoft = Color(0xFF8FB8F5);
  static const Color accent = Color(0xFFA9CCFB);

  static const Color background = Color(0xFF0B1220);
  static const Color surface = Color(0xFF141C2E);
  static const Color surfaceVariant = Color(0xFF1B2740);
  static const Color surfaceSunken = Color(0xFF0F1626);

  static const Color border = Color(0xFF293550);
  static const Color borderStrong = Color(0xFF384969);

  static const Color textPrimary = Color(0xFFEAF1FB);
  static const Color textSecondary = Color(0xFFA9B9CE);
  static const Color textTertiary = Color(0xFF7689A3);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFE2A93B);
  static const Color danger = Color(0xFFEF6B6B);

  static const Color shadow = Color(0xFF000814);

  /// Lighter than the dark background on purpose, so a snackbar or tooltip
  /// still reads as a raised chip instead of vanishing into it.
  static const Color inverseSurface = Color(0xFF2A3B57);

  static const Map<String, Color> map = {
    'primary': primary,
    'primaryDark': primaryDark,
    'primarySoft': primarySoft,
    'accent': accent,
    'background': background,
    'surface': surface,
    'surfaceVariant': surfaceVariant,
    'surfaceSunken': surfaceSunken,
    'border': border,
    'borderStrong': borderStrong,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'textTertiary': textTertiary,
    'success': success,
    'warning': warning,
    'danger': danger,
    'shadow': shadow,
    'inverseSurface': inverseSurface,
  };
}
