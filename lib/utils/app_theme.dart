import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_styles.dart';

class AppTheme {
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.panicPrimary,
        secondary: AppColors.panicSecondary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        headlineSmall: AppStyles.titleStyle,
        titleMedium: AppStyles.sectionTitleStyle,
        bodyMedium: AppStyles.bodyStyle,
        bodySmall: AppStyles.captionStyle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.panicPrimary, width: 1.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.panicPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.panicPrimary.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
