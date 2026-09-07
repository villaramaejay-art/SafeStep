import 'package:flutter/material.dart';

/// SafeStep's palette. The blue identity is unchanged; the status colours are
/// the additions, so "inside your safe zone" and "something failed" no longer
/// have to borrow the brand blue.
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primarySoft = Color(0xFF60A5FA);
  static const Color accent = Color(0xFF93C5FD);

  // Surfaces
  static const Color background = Color(0xFFF6FAFF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFEAF4FF);
  static const Color surfaceSunken = Color(0xFFF1F7FE);

  // Lines
  static const Color border = Color(0xFFDDEBFA);
  static const Color borderStrong = Color(0xFFC3DBF4);

  // Text
  static const Color textPrimary = Color(0xFF10304A);
  static const Color textSecondary = Color(0xFF5D738B);
  static const Color textTertiary = Color(0xFF8CA0B6);

  // Status
  static const Color success = Color(0xFF0FA97D);
  static const Color warning = Color(0xFFB86E00);
  static const Color danger = Color(0xFFD14343);

  static const Color shadow = Color(0xFFB7D8F8);
}
