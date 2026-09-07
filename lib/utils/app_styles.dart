import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

/// The type scale and the surface treatments. Screens should reach for these
/// instead of writing one-off TextStyles and BoxDecorations.
class AppStyles {
  const AppStyles._();

  // --- Type scale -----------------------------------------------------------

  static const TextStyle displayStyle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionTitleStyle = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMutedStyle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  /// Small all-caps label above a group of controls.
  static const TextStyle overlineStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.9,
    color: AppColors.textTertiary,
  );

  // --- Surfaces -------------------------------------------------------------

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: 0.22),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  /// The default raised card.
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppSpacing.large,
        border: Border.all(color: AppColors.border),
        boxShadow: softShadow,
      );

  /// A card nested inside another card - no shadow, so they do not stack up.
  static BoxDecoration get flatCardDecoration => BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppSpacing.medium,
        border: Border.all(color: AppColors.border),
      );

  /// A tinted panel for supporting information.
  static BoxDecoration get tintedDecoration => BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppSpacing.large,
        border: Border.all(color: AppColors.border),
      );

  /// A recessed area, for things sitting on top of a card.
  static BoxDecoration get sunkenDecoration => BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: AppSpacing.medium,
      );

  /// Tinted status panel, e.g. an inline error or hint.
  static BoxDecoration statusDecoration(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: AppSpacing.medium,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      );

  /// Rounded pill used for badges and counters.
  static BoxDecoration pillDecoration(Color color) => BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppSpacing.rounded,
      );

  /// Square icon chip that fronts most list rows and cards.
  static BoxDecoration iconTileDecoration({Color? color}) => BoxDecoration(
        color: (color ?? AppColors.primary).withValues(alpha: 0.12),
        borderRadius: AppSpacing.medium,
      );
}
