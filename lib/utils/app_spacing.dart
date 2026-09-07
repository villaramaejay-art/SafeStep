import 'package:flutter/material.dart';

/// One spacing and radius scale for the whole app, so screens stop inventing
/// their own 14s, 18s and 22s.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double xxxl = 40;

  /// Standard horizontal inset for a screen body.
  static const EdgeInsets page = EdgeInsets.fromLTRB(xl, md, xl, xl);

  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 26;
  static const double pill = 999;

  static BorderRadius get small => BorderRadius.circular(radiusSm);
  static BorderRadius get medium => BorderRadius.circular(radiusMd);
  static BorderRadius get large => BorderRadius.circular(radiusLg);
  static BorderRadius get extraLarge => BorderRadius.circular(radiusXl);
  static BorderRadius get rounded => BorderRadius.circular(pill);

  /// Vertical gaps, so `const Gap.lg` reads better than a bare SizedBox.
  static const Widget gapXs = SizedBox(height: xs);
  static const Widget gapSm = SizedBox(height: sm);
  static const Widget gapMd = SizedBox(height: md);
  static const Widget gapLg = SizedBox(height: lg);
  static const Widget gapXl = SizedBox(height: xl);
  static const Widget gapXxl = SizedBox(height: xxl);

  static const Widget hGapSm = SizedBox(width: sm);
  static const Widget hGapMd = SizedBox(width: md);
  static const Widget hGapLg = SizedBox(width: lg);
}
