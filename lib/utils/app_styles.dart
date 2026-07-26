import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppStyles {
  static const TextStyle titleStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle sectionTitleStyle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const TextStyle captionStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static BoxDecoration cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: AppColors.border, width: 1),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFFB7D8F8).withValues(alpha: 0.28),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
    ],
  );
}
