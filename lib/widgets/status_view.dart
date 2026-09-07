import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';

/// The empty / error / loading placeholder used by the list screens, so they
/// all speak with the same visual voice.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.tone,
    this.action,
  });

  /// A centred spinner with a caption, for first load.
  const StatusView.loading({super.key, required this.message})
      : icon = null,
        title = null,
        tone = null,
        action = null;

  final IconData? icon;
  final String? title;
  final String message;

  /// Accent for the icon; defaults to the brand blue.
  final Color? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? AppColors.primary;
    final isLoading = icon == null && title == null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              Container(
                width: 76,
                height: 76,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: color),
              ),
            AppSpacing.gapLg,
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: AppStyles.sectionTitleStyle,
              ),
              AppSpacing.gapSm,
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppStyles.bodyMutedStyle,
            ),
            if (action != null) ...[AppSpacing.gapXl, action!],
          ],
        ),
      ),
    );
  }
}
