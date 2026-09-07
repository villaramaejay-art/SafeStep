import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/safe_space.dart';
import '../services/arrival_watcher.dart';
import '../services/contacts_repository.dart' show RepositoryFailure;
import '../services/emergency_service.dart';
import '../services/location_service.dart';
import '../services/safe_spaces_repository.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../widgets/alert_countdown_dialog.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  static const List<int> _presets = [10, 20, 30, 60];

  final EmergencyService _emergencyService = EmergencyService();
  final SafeSpacesRepository _safeSpacesRepository = SafeSpacesRepository();
  final LocationService _locationService = LocationService();
  final ArrivalWatcher _arrivalWatcher = const ArrivalWatcher();

  int _selectedMinutes = 10;
  late Duration _remaining = Duration(minutes: _selectedMinutes);
  Timer? _timer;

  /// Watches for the user reaching a safe space while the timer runs, so
  /// getting home is the check-in. Live only while the countdown is.
  StreamSubscription<LocationFix>? _arrivalSubscription;
  List<SafeSpace> _safeSpaces = [];
  bool _isWatchingArrival = false;

  /// True once a fix has put the user outside every safe space.
  ///
  /// Arrival has to be a transition, not just "is inside now". Without this, a
  /// timer started at home - which is the normal way to start one before going
  /// out - would cancel itself on the first fix and never protect anything.
  bool _hasLeftSafeSpace = false;

  bool get _isRunning => _timer?.isActive ?? false;
  bool get _hasStarted => _remaining.inSeconds < _selectedMinutes * 60;
  int get _totalSeconds => _selectedMinutes * 60;

  double get _progress =>
      (_remaining.inSeconds / _totalSeconds).clamp(0.0, 1.0).toDouble();

  String get _timerText {
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = _remaining.inHours;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String get _durationLabel =>
      _selectedMinutes >= 60 ? '1 hour' : '$_selectedMinutes minutes';

  /// Clock time the countdown reaches zero, so the user can compare it against
  /// when they actually expect to be somewhere.
  String get _endsAtText {
    final endsAt = DateTime.now().add(_remaining);
    final hour = endsAt.hour % 12 == 0 ? 12 : endsAt.hour % 12;
    final minute = endsAt.minute.toString().padLeft(2, '0');

    return '$hour:$minute ${endsAt.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _arrivalSubscription?.cancel();
    super.dispose();
  }

  // --- Arriving somewhere safe ----------------------------------------------

  /// Starts watching for the user reaching a safe space.
  ///
  /// Best effort throughout: no safe spaces, no location permission or no fix
  /// all just mean the timer behaves as it always did and the user checks in by
  /// hand. None of them is worth stopping a running safety timer over.
  Future<void> _watchForArrival() async {
    if (_arrivalSubscription != null) return;

    try {
      _safeSpaces = await _safeSpacesRepository.fetchAll();
    } on RepositoryFailure {
      return;
    }

    if (_safeSpaces.isEmpty || !mounted || !_isRunning) return;

    try {
      await _locationService.ensurePermission();
    } on LocationException {
      return;
    }

    if (!mounted || !_isRunning) return;

    _arrivalSubscription = _locationService.watchFixes().listen(
      _checkArrival,
      onError: (_) {
        // The timer keeps running; only the shortcut home is lost.
        _stopWatchingArrival();
      },
    );

    setState(() => _isWatchingArrival = true);

    // The stream only emits after ten metres of movement, so somebody standing
    // still would never be evaluated at all. One fix now seeds the inside or
    // outside verdict the arrival test depends on.
    final fix = await _locationService.getFixForAlert();
    if (fix != null && mounted && _isRunning) _checkArrival(fix);
  }

  void _stopWatchingArrival() {
    _arrivalSubscription?.cancel();
    _arrivalSubscription = null;
    _hasLeftSafeSpace = false;

    if (mounted && _isWatchingArrival) {
      setState(() => _isWatchingArrival = false);
    }
  }

  /// The safe space the user is in at this moment, or null.
  ///
  /// Takes its own fix rather than trusting the last one the stream happened to
  /// deliver: with a ten metre movement filter, that reading can be minutes old
  /// and describe somewhere the user has since left.
  Future<SafeSpace?> _safeSpaceRightNow() async {
    if (_safeSpaces.isEmpty) return null;

    final fix = await _locationService.getFixForAlert();
    if (fix == null) return null;

    return _arrivalWatcher.arrivedAt(fix.point, fix.accuracy, _safeSpaces);
  }

  void _checkArrival(LocationFix fix) {
    if (!mounted || !_isRunning) return;

    final arrived = _arrivalWatcher.arrivedAt(
      fix.point,
      fix.accuracy,
      _safeSpaces,
    );

    if (arrived == null) {
      // Outside everything - now a return can mean something.
      _hasLeftSafeSpace = true;
      return;
    }

    // Inside, but the user never went anywhere: this is a timer set before
    // heading out, and cancelling it here would make the timer impossible to
    // arm from home.
    if (!_hasLeftSafeSpace) return;

    // Getting there is the check-in. Pressing pause afterwards was a step that
    // only existed because the app could not tell.
    _cancelTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Arrived at ${arrived.name}. Safety timer stopped.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _setPreset(int minutes) {
    _timer?.cancel();
    _stopWatchingArrival();
    setState(() {
      _selectedMinutes = minutes;
      _remaining = Duration(minutes: minutes);
    });
  }

  void _startTimer() {
    _timer?.cancel();

    if (_remaining.inSeconds <= 0) {
      _remaining = Duration(minutes: _selectedMinutes);
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

    _watchForArrival();
  }

  void _pauseTimer() {
    _timer?.cancel();
    _stopWatchingArrival();
    setState(() {});
  }

  void _cancelTimer() {
    _timer?.cancel();
    _stopWatchingArrival();
    setState(() => _remaining = Duration(minutes: _selectedMinutes));
  }

  /// The switch has tripped: alert the contacts unless the user checks in
  /// during the grace period.
  Future<void> _showTimerFinishedAlert() async {
    if (!mounted) return;

    // Before anything else: is the user demonstrably somewhere safe?
    //
    // A deadline passing means "we have not heard from you". If the phone can
    // see the user sitting inside a zone they told us is safe, that question is
    // already answered, and texting contacts for help would be a false alarm
    // raised about somebody who is at home.
    final arrived = await _safeSpaceRightNow();

    if (arrived != null) {
      if (!mounted) return;
      _cancelTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Timer ended, but you are inside ${arrived.name}. No alert sent.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
      return;
    }

    if (!mounted) return;

    final shouldAlert = await AlertCountdownDialog.show(
      context,
      title: 'Safety check needed',
      detail: 'Your timer ended. SafeStep will text your emergency contacts '
          'with your location unless you check in.',
      seconds: 10,
      cancelLabel: "I'm safe - cancel",
    );

    if (!mounted) return;

    if (!shouldAlert) {
      _cancelTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checked in. No alert was sent.')),
      );
      return;
    }

    final outcome = await _emergencyService.sendAlert(
      reason: AlertReason.timerExpired,
    );

    if (!mounted) return;

    _cancelTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.summary),
        backgroundColor:
            outcome.isSuccess ? AppColors.success : AppColors.danger,
      ),
    );
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
    } else if (_hasStarted) {
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
                const Text(
                  "Dead Man's Switch",
                  style: AppStyles.sectionTitleStyle,
                ),
                const SizedBox(height: 3),
                Text(
                  // The auto-stop has to be stated, or arriving home and
                  // watching the timer vanish looks like a bug.
                  _isWatchingArrival
                      ? 'Alerts your contacts if it runs out. Stops on its own '
                          'when you reach a safe space.'
                      : 'If no activity is detected, SafeStep alerts your '
                          'contacts.',
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
                  : _hasStarted
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
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        color: AppColors.textPrimary,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _hasStarted ? 'remaining' : _durationLabel,
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
                // nothing is happening. The time it ends is the fact the user
                // does not otherwise have.
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
                                  : _hasStarted
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
                            onPressed: _hasStarted ? _cancelTimer : null,
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
              const Text('CHECK-IN AFTER', style: AppStyles.overlineStyle),
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
