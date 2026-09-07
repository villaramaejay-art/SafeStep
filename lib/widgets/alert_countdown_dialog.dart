import 'dart:async';

import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';

/// A short grace period before an alert goes out.
///
/// Emergency SMS costs real money and alarms real people, so an accidental tap
/// or a GPS glitch should be cancellable. Returns true to send, false to abort.
class AlertCountdownDialog extends StatefulWidget {
  const AlertCountdownDialog({
    super.key,
    required this.title,
    required this.detail,
    this.seconds = 5,
    this.cancelLabel = 'Cancel',
  });

  final String title;
  final String detail;
  final int seconds;
  final String cancelLabel;

  /// Shows the dialog. It cannot be dismissed by tapping outside, so the
  /// choice is always deliberate.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String detail,
    int seconds = 5,
    String cancelLabel = 'Cancel',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertCountdownDialog(
        title: title,
        detail: detail,
        seconds: seconds,
        cancelLabel: cancelLabel,
      ),
    );
    return result ?? false;
  }

  @override
  State<AlertCountdownDialog> createState() => _AlertCountdownDialogState();
}

class _AlertCountdownDialogState extends State<AlertCountdownDialog> {
  late int _remaining = widget.seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() => _remaining--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _close(bool send) {
    _timer?.cancel();
    Navigator.of(context).pop(send);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _remaining / widget.seconds;

    return AlertDialog(
      icon: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                color: AppColors.danger,
                backgroundColor: AppColors.border,
              ),
            ),
            Text(
              '$_remaining',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.danger,
              ),
            ),
          ],
        ),
      ),
      title: Text(widget.title, textAlign: TextAlign.center),
      content: Text(
        widget.detail,
        textAlign: TextAlign.center,
        style: AppStyles.bodyMutedStyle,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                  onPressed: () => _close(true),
                  icon: const Icon(Icons.sms_rounded, size: 18),
                  label: const Text('Send now'),
                ),
              ),
              AppSpacing.gapSm,
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _close(false),
                  child: Text(widget.cancelLabel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
