import 'package:flutter/material.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';

/// A tinted inline message: form errors, hints, and confirmations.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    required this.icon,
    required this.color,
    this.margin,
  });

  final String message;
  final IconData icon;
  final Color color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppStyles.statusDecoration(color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              message,
              style: AppStyles.captionStyle.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
