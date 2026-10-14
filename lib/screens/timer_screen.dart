import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../services/background/foreground_service_controller.dart';
import '../services/background/safety_task_handler.dart';
import '../services/timer_session_repository.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../widgets/alert_countdown_dialog.dart';

/// A view and remote control for the Safety Timer - not where the countdown
/// actually runs.
///
/// The countdown, the "arrived at a safe space disarms it" watch, and the
/// alert dispatch all live in [SafetyTaskHandler], running inside a
/// foreground service so they keep working with this screen closed, the app
/// backgrounded, or the phone locked. This screen only sends commands
/// (`start`/`pause`/`resume`/`cancel`/`checkIn`) and renders whatever state
/// the service last reported - see docs/plans/sharded-prancing-puddle.md.
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  static const List<int> _presets = [10, 20, 30, 60];

  TimerSession _session = TimerSession.inactive;
  int _selectedMinutes = 10;
  Timer? _uiTicker;
  bool _checkInDialogOpen = false;

  bool get _isRunning => _session.status == TimerSessionStatus.running;
  bool get _isPaused => _session.status == TimerSessionStatus.paused;
  bool get _hasActiveSession => _session.status != TimerSessionStatus.inactive;
  bool get _isWatchingArrival => _session.isWatchingArrival;

  int get _minutesForDisplay => _session.selectedMinutes ?? _selectedMinutes;
  int get _totalSeconds => _minutesForDisplay * 60;

  Duration get _remaining {
    switch (_session.status) {
      case TimerSessionStatus.running:
        return _session.remainingAt(DateTime.now());
      case TimerSessionStatus.paused:
        return Duration(milliseconds: _session.pausedRemainingMs ?? 0);
      case TimerSessionStatus.awaitingCheckIn:
      case TimerSessionStatus.expired:
        return Duration.zero;
      case TimerSessionStatus.inactive:
        return Duration(minutes: _minutesForDisplay);
    }
  }

  double get _progress {
    if (_totalSeconds == 0) return 0;
    return (_remaining.inSeconds / _totalSeconds).clamp(0.0, 1.0).toDouble();
  }

  String get _timerText {
    final remaining = _remaining;
    final minutes = remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = remaining.inHours;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String get _durationLabel =>
      _minutesForDisplay >= 60 ? '1 hour' : '$_minutesForDisplay minutes';

  /// Clock time the countdown reaches zero, so the user can compare it
  /// against when they actually expect to be somewhere. Works whether or not
  /// the timer is running: `_remaining` is the full duration until started.
  String get _endsAtText {
    final endsAt = DateTime.now().add(_remaining);
    final hour = endsAt.hour % 12 == 0 ? 12 : endsAt.hour % 12;
    final minute = endsAt.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${endsAt.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  void initState() {
    super.initState();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    // Purely cosmetic: re-renders the countdown digits once a second between
    // the service's own reports, which may arrive less often than that under
    // Doze-style throttling. The service's persisted deadline is still what
    // actually decides when the timer ends - this just keeps the display
    // from looking frozen while it waits for the next report.
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRunning) setState(() {});
    });

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    ForegroundServiceController.configure();
    await ForegroundServiceController.requestPermissions();

    final persisted = await TimerSessionRepository().load();
    if (!mounted) return;

    setState(() {
      _session = persisted;
      final minutes = persisted.selectedMinutes;
      if (minutes != null) _selectedMinutes = minutes;
    });

    // The app may have been opened after the grace notification already
    // fired while it was closed - show the same check-in prompt now rather
    // than leaving it to only the notification's own button.
    if (persisted.status == TimerSessionStatus.awaitingCheckIn) {
      _showCheckInDialog();
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    _uiTicker?.cancel();
    super.dispose();
  }

  // --- Messages from the service ---------------------------------------------

  void _onReceiveTaskData(Object data) {
    if (data is! Map) return;

    final sessionMap = data['session'];
    if (sessionMap is Map) {
      final wasAwaitingCheckIn =
          _session.status == TimerSessionStatus.awaitingCheckIn;
      final updated = TimerSession.fromMap(sessionMap);

      if (!mounted) return;
      setState(() {
        _session = updated;
        final minutes = updated.selectedMinutes;
        if (minutes != null) _selectedMinutes = minutes;
      });

      if (!wasAwaitingCheckIn &&
          updated.status == TimerSessionStatus.awaitingCheckIn) {
        _showCheckInDialog();
      }
    }

    final event = data['event'];
    if (event is String) _handleEvent(event, data);
  }

  void _handleEvent(String event, Map data) {
    switch (event) {
      case 'arrived_during_countdown':
        _notify(
          'Arrived at ${data['safeSpace']}. Safety timer stopped.',
          AppColors.success,
        );
      case 'timer_ended_but_safe':
        _notify(
          'Timer ended, but you are inside ${data['safeSpace']}. '
          'No alert sent.',
          AppColors.success,
        );
      case 'alert_sent':
        final success = data['success'] as bool? ?? false;
        _notify(
          data['summary'] as String? ?? 'Alert sent.',
          success ? AppColors.success : AppColors.danger,
        );
      case 'checked_in':
        _notify('Checked in. No alert was sent.', AppColors.primary);
    }
  }

  void _notify(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  /// Mirrors the in-app grace-period dialog this screen always had. The
  /// service is the one actually enforcing the deadline and sending the
  /// alert - this dialog is a convenience for whenever the app happens to be
  /// open, not a second authority. Cancelling sends the same `checkIn`
  /// command the notification's own button sends; letting the dialog's
  /// local countdown run out sends nothing; the service's own clock has
  /// already decided that case independently by the time it would.
  Future<void> _showCheckInDialog() async {
    if (_checkInDialogOpen || !mounted) return;
    _checkInDialogOpen = true;

    final seconds = _session
        .graceRemainingAt(DateTime.now())
        .inSeconds
        .clamp(1, SafetyTaskHandler.graceWindow.inSeconds);

    final shouldAlert = await AlertCountdownDialog.show(
      context,
      title: 'Safety check needed',
      detail: 'Your timer ended. SafeStep will text your emergency contacts '
          'with your location unless you check in.',
      seconds: seconds,
      cancelLabel: "I'm safe - cancel",
    );

    _checkInDialogOpen = false;
    if (!shouldAlert) {
      FlutterForegroundTask.sendDataToTask({'cmd': 'checkIn'});
    }
  }

  // --- Commands to the service ------------------------------------------------

  Future<void> _ensureServiceRunning() async {
    if (await ForegroundServiceController.isRunning) return;
    await ForegroundServiceController.start(
      title: 'Safety timer running',
      text: 'Starting...',
    );
  }

  void _setPreset(int minutes) {
    setState(() => _selectedMinutes = minutes);
    if (_hasActiveSession) {
      FlutterForegroundTask.sendDataToTask({'cmd': 'cancel'});
    }
  }

  Future<void> _startTimer() async {
    await _ensureServiceRunning();
    if (_isPaused) {
      FlutterForegroundTask.sendDataToTask({'cmd': 'resume'});
    } else {
      FlutterForegroundTask.sendDataToTask({
        'cmd': 'start',
        'minutes': _selectedMinutes,
      });
    }
  }

  void _pauseTimer() {
    FlutterForegroundTask.sendDataToTask({'cmd': 'pause'});
  }

  void _cancelTimer() {
    FlutterForegroundTask.sendDataToTask({'cmd': 'cancel'});
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildStatusHeader() {
    final Color tone;
    final String status;
    final IconData icon;

    if (_isRunning) {
      tone = AppColors.success;
      status = 'Monitoring';
      icon = Icons.shield_rounded;
    } else if (_isPaused) {
      tone = AppColors.warning;
      status = 'Paused';
      icon = Icons.pause_circle_outline_rounded;
    } else {
      tone = AppColors.textTertiary;
      status = 'Standby';
      icon = Icons.shield_outlined;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.tintedDecoration,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppSpacing.medium,
            ),
            child: Icon(icon, color: tone, size: 22),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Dead Man's Switch",
                  style: AppStyles.sectionTitleStyle,
                ),
                const SizedBox(height: 3),
                Text(
                  // The auto-stop has to be stated, or arriving home and
                  // watching the timer vanish looks like a bug.
                  _isWatchingArrival
                      ? 'Alerts your contacts if it runs out. Stops on its own '
                          'when you reach a safe space. Keeps watching with '
                          'the app closed or the screen locked.'
                      : 'If no activity is detected, SafeStep alerts your '
                          'contacts - even with the app closed or the screen '
                          'locked.',
                  style: AppStyles.captionStyle,
                ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 5,
            ),
            decoration: AppStyles.pillDecoration(tone),
            child: Text(
              status,
              style: TextStyle(
                color: tone,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDial() {
    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(250),
            painter: _TimerRingPainter(
              progress: _progress,
              progressColor: _isRunning
                  ? AppColors.primary
                  : _isPaused
                      ? AppColors.warning
                      : AppColors.primarySoft,
              trackColor: AppColors.border,
            ),
          ),
          Container(
            width: 178,
            height: 178,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow.withValues(alpha: 0.3),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _timerText,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: AppColors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasActiveSession ? 'remaining' : _durationLabel,
                  style: AppStyles.captionStyle,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 4,
              ),
              decoration: AppStyles.pillDecoration(
                _isRunning ? AppColors.primary : AppColors.textTertiary,
              ),
              child: Text(
                // A percentage of a countdown says nothing the ring and the
                // digits are not already saying, and reads "100%" while
                // nothing is happening. The time it ends is the fact the
                // user does not otherwise have.
                _isRunning ? 'Ends $_endsAtText' : _durationLabel,
                style: TextStyle(
                  color: _isRunning ? AppColors.primary : AppColors.textTertiary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    return Row(
      children: [
        for (final minutes in _presets) ...[
          Expanded(
            child: _PresetChip(
              label: minutes == 60 ? '1 hr' : '$minutes m',
              selected: minutes == _selectedMinutes,
              onTap: () => _setPreset(minutes),
            ),
          ),
          if (minutes != _presets.last) AppSpacing.hGapSm,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Safety Timer'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusHeader(),
              AppSpacing.gapLg,
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  children: [
                    _buildDial(),
                    AppSpacing.gapXl,
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isRunning ? _pauseTimer : _startTimer,
                            icon: Icon(
                              _isRunning
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 20,
                            ),
                            label: Text(
                              _isRunning
                                  ? 'Pause'
                                  : _isPaused
                                      ? 'Resume'
                                      : 'Start Timer',
                            ),
                          ),
                        ),
                        AppSpacing.hGapMd,
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _hasActiveSession ? _cancelTimer : null,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.zero,
                            ),
                            child: const Icon(Icons.refresh_rounded, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              AppSpacing.gapXl,
              Text('CHECK-IN AFTER', style: AppStyles.overlineStyle),
              AppSpacing.gapMd,
              _buildPresets(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A duration option. A plain chip is too small a tap target for this row.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      borderRadius: AppSpacing.medium,
      child: InkWell(
        borderRadius: AppSpacing.medium,
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppSpacing.medium,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
    final radius = (size.shortestSide - 16) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..shader = SweepGradient(
        colors: [progressColor.withValues(alpha: 0.65), progressColor],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
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
