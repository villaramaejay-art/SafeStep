import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  int selectedMinutes = 10;
  late Duration _remaining = Duration(minutes: selectedMinutes);
  Timer? _timer;

  bool get _isRunning => _timer?.isActive ?? false;
  bool get _hasStarted => _remaining.inSeconds < selectedMinutes * 60;
  int get _totalSeconds => selectedMinutes * 60;
  double get _progress {
    return (_remaining.inSeconds / _totalSeconds).clamp(0.0, 1.0).toDouble();
  }

  String get _timerText {
    final minutes = _remaining.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = _remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final hours = _remaining.inHours;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  String get _durationLabel {
    if (selectedMinutes >= 60) return '1 hour';
    return '$selectedMinutes minutes';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setPreset(int minutes) {
    _timer?.cancel();
    setState(() {
      selectedMinutes = minutes;
      _remaining = Duration(minutes: minutes);
    });
  }

  void _startTimer() {
    _timer?.cancel();

    if (_remaining.inSeconds <= 0) {
      _remaining = Duration(minutes: selectedMinutes);
    }

    setState(() {});

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining.inSeconds <= 1) {
        timer.cancel();
        setState(() => _remaining = Duration.zero);
        _showTimerFinishedAlert();
        return;
      }

      setState(() {
        _remaining = Duration(seconds: _remaining.inSeconds - 1);
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() {});
  }

  void _cancelTimer() {
    _timer?.cancel();
    setState(() {
      _remaining = Duration(minutes: selectedMinutes);
    });
  }

  Future<void> _showTimerFinishedAlert() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Safety check needed'),
          content: const Text(
            'Your timer ended. Check in now or notify your emergency contacts.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _cancelTimer();
              },
              child: const Text('Reset'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _setPreset(selectedMinutes);
                _startTimer();
              },
              child: const Text('Restart'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.panicPrimary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppStyles.captionStyle),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _isRunning
        ? 'Timer is active'
        : _hasStarted
            ? 'Timer paused'
            : 'Ready to start';

    return Scaffold(
      appBar: AppBar(title: const Text('Safety Timer')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.panicPrimary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _isRunning
                                ? Icons.timer_rounded
                                : Icons.timer_outlined,
                            color: AppColors.panicPrimary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dead Man\'s Switch',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                statusText,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'If no activity is detected, the app will alert your contacts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: 248,
                      height: 248,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: const Size.square(248),
                            painter: _TimerRingPainter(
                              progress: _progress,
                              progressColor: _isRunning
                                  ? AppColors.panicPrimary
                                  : AppColors.panicSecondary,
                              trackColor: AppColors.border,
                            ),
                          ),
                          Container(
                            width: 176,
                            height: 176,
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.panicPrimary.withValues(
                                    alpha: 0.08,
                                  ),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      _timerText,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        fontSize: 42,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _hasStarted ? 'remaining' : _durationLabel,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: (_isRunning
                                        ? AppColors.panicPrimary
                                        : AppColors.panicSecondary)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${(_progress * 100).round()}%',
                                style: TextStyle(
                                  color: _isRunning
                                      ? AppColors.panicPrimary
                                      : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        _buildInfoTile(
                          icon: Icons.shield_outlined,
                          label: 'Mode',
                          value: _isRunning ? 'Monitoring' : 'Standby',
                        ),
                        const SizedBox(width: 12),
                        _buildInfoTile(
                          icon: Icons.notifications_active_outlined,
                          label: 'Action',
                          value: 'Alert contacts',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [10, 20, 30, 60].map((minutes) {
                        final selected = minutes == selectedMinutes;
                        return ChoiceChip(
                          avatar: selected
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                          label: Text(minutes == 60 ? '1hr' : '${minutes}m'),
                          selected: selected,
                          onSelected: (_) => _setPreset(minutes),
                          selectedColor: AppColors.panicPrimary,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isRunning ? _pauseTimer : _startTimer,
                            icon: Icon(
                              _isRunning
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              _isRunning
                                  ? 'Pause Timer'
                                  : _hasStarted
                                      ? 'Resume Timer'
                                      : 'Start Timer',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: IconButton.filledTonal(
                            onPressed: _hasStarted ? _cancelTimer : null,
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Reset timer',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  const _TimerRingPainter({
    required this.progress,
    required this.progressColor,
    required this.trackColor,
  });

  final double progress;
  final Color progressColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 18) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          progressColor.withValues(alpha: 0.72),
          progressColor,
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _TimerRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}
