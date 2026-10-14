import 'dart:async';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import '../../models/safe_space.dart';
import '../alert_cooldown_store.dart';
import '../arrival_watcher.dart';
import '../contacts_repository.dart' show RepositoryFailure;
import '../emergency_service.dart';
import '../location_service.dart';
import '../safe_spaces_repository.dart';
import '../timer_session_repository.dart';

/// Entry point the OS/plugin calls to attach [SafetyTaskHandler] inside the
/// foreground service's own isolate. Must stay top-level (or static) and
/// keep this annotation, or release builds strip it and the service has
/// nothing to run.
@pragma('vm:entry-point')
void safetyTaskHandlerStartCallback() {
  // Without this, any plugin that eagerly touches a MethodChannel during
  // construction - another_telephony's Telephony.instance, reached via
  // EmergencyService's constructor, is the one that actually hit this -
  // crashes immediately: this isolate never ran WidgetsFlutterBinding's
  // normal startup, so ServicesBinding.instance is null here until this runs.
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(SafetyTaskHandler());
}

/// Runs the Safety Timer's whole lifecycle - countdown, the "arrived at a
/// safe space disarms it" watch, the expiry grace period, and the actual
/// alert dispatch - inside the foreground service's isolate, independent of
/// whether `TimerScreen` is even mounted.
///
/// This is the only place in the app that ever calls
/// `EmergencyService.sendAlert(reason: AlertReason.timerExpired)`. Moving
/// that call here instead of leaving it in `_TimerScreenState` is what makes
/// a duplicate alert structurally impossible, rather than something two
/// independent timers would have to coordinate around after the fact -
/// `TimerScreen` now only sends commands and reflects whatever state this
/// handler last reported.
class SafetyTaskHandler extends TaskHandler {
  /// How long a check-in notification waits before the alert actually sends.
  /// Longer than the in-app dialog's 10s: there is no live countdown to read
  /// here, and the user has to unlock the phone first.
  static const Duration graceWindow = Duration(seconds: 30);

  final TimerSessionRepository _sessions = TimerSessionRepository();
  final LocationService _locationService = LocationService();
  final ArrivalWatcher _arrivalWatcher = const ArrivalWatcher();

  // Deliberately not constructed until Supabase has been initialized in this
  // isolate (see onStart): both default to `Supabase.instance.client` in
  // their own constructors, which throws if nothing has initialized it yet -
  // a field initializer here would run before onStart gets the chance to.
  late final EmergencyService _emergencyService;
  late final SafeSpacesRepository _safeSpacesRepository;

  TimerSession _session = TimerSession.inactive;
  List<SafeSpace> _safeSpaces = [];
  StreamSubscription<LocationFix>? _arrivalSubscription;

  /// True once a fix has put the user outside every safe space. Arrival has
  /// to be a transition, not just "is inside now" - otherwise a timer
  /// started at home, which is the normal way to arm one before heading out,
  /// would cancel itself on the very first fix and never protect anything.
  bool _hasLeftSafeSpace = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await AlertCooldownStore.hydrate();
    await _ensureSupabase();

    _emergencyService = EmergencyService();
    _safeSpacesRepository = SafeSpacesRepository();

    _session = await _sessions.load();

    // Recovering after a restart: if the deadline (or the grace window)
    // already passed while nothing was alive to see it, run that flow now
    // instead of waiting for the next tick - which would reach the same
    // place anyway, just later, and the first state the UI reads should
    // already reflect what actually happened.
    final now = DateTime.now();
    if (_session.status == TimerSessionStatus.running &&
        _session.isPastDeadline) {
      await _handleDeadlineReached();
    } else if (_session.status == TimerSessionStatus.awaitingCheckIn &&
        _session.isPastGraceDeadline(now)) {
      await _dispatchAlert();
    } else if (_session.status == TimerSessionStatus.running) {
      await _startArrivalWatch();
    }

    _reportState();
  }

  /// Safe to call from a fresh isolate (nothing initialized yet) or a
  /// restarted service inside an isolate that already did this once - either
  /// way it recovers the session already on disk rather than needing a
  /// fresh login.
  Future<void> _ensureSupabase() async {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.key,
      );
    } catch (_) {
      // Already initialized in this isolate, or genuinely unreachable - the
      // dispatch path reports its own failure either way.
    }
  }

  // --- Commands from the UI --------------------------------------------------

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;

    switch (data['cmd']) {
      case 'start':
        final minutes = (data['minutes'] as num?)?.toInt();
        if (minutes != null) unawaited(_start(minutes));
      case 'pause':
        unawaited(_pause());
      case 'resume':
        unawaited(_resume());
      case 'cancel':
        unawaited(_cancel());
      case 'checkIn':
        unawaited(_checkIn());
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'checkin') unawaited(_checkIn());
  }

  Future<void> _start(int minutes) async {
    _hasLeftSafeSpace = false;
    _session = TimerSession(
      status: TimerSessionStatus.running,
      deadline: DateTime.now().add(Duration(minutes: minutes)),
      selectedMinutes: minutes,
    );
    await _persist();
    await _startArrivalWatch();
    _reportState();
  }

  Future<void> _pause() async {
    if (_session.status != TimerSessionStatus.running) return;

    final remaining = _session.remainingAt(DateTime.now());
    _session = _session.copyWith(
      status: TimerSessionStatus.paused,
      clearDeadline: true,
      pausedRemainingMs: remaining.inMilliseconds,
    );
    await _stopArrivalWatch();
    await _persist();
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Safety timer paused',
      notificationText: 'Resume from the app to keep watching.',
    );
    _reportState();
  }

  Future<void> _resume() async {
    if (_session.status != TimerSessionStatus.paused) return;

    final remainingMs = _session.pausedRemainingMs ?? 0;
    _hasLeftSafeSpace = false;
    _session = _session.copyWith(
      status: TimerSessionStatus.running,
      deadline: DateTime.now().add(Duration(milliseconds: remainingMs)),
      clearPausedRemainingMs: true,
    );
    await _persist();
    await _startArrivalWatch();
    _reportState();
  }

  Future<void> _cancel() async {
    final minutes = _session.selectedMinutes;
    await _stopArrivalWatch();
    _session = TimerSession(
      status: TimerSessionStatus.inactive,
      selectedMinutes: minutes,
    );
    await _persist();
    _reportState();
  }

  Future<void> _checkIn() async {
    if (_session.status != TimerSessionStatus.awaitingCheckIn) return;
    await _cancel();
    FlutterForegroundTask.sendDataToMain({'event': 'checked_in'});
  }

  // --- Arriving somewhere safe ------------------------------------------------

  /// Best effort throughout: no safe spaces, no location permission, or no
  /// fix all just mean the timer behaves as a plain countdown and the user
  /// checks in by hand. None of them is worth failing a running timer over.
  Future<void> _startArrivalWatch() async {
    if (_arrivalSubscription != null) return;

    try {
      _safeSpaces = await _safeSpacesRepository.fetchAll();
    } on RepositoryFailure {
      return;
    }
    if (_safeSpaces.isEmpty) return;

    try {
      await _locationService.ensurePermission();
    } on LocationException {
      return;
    }

    _arrivalSubscription = _locationService.watchFixes().listen(
      _checkArrival,
      onError: (_) => _stopArrivalWatch(),
    );
    _session = _session.copyWith(isWatchingArrival: true);
    await _persist();

    // The stream only emits after ten metres of movement, so somebody
    // standing still would never be evaluated at all. One fix now seeds the
    // inside-or-outside verdict the arrival test depends on.
    final fix = await _locationService.getFixForAlert();
    if (fix != null) _checkArrival(fix);
  }

  Future<void> _stopArrivalWatch() async {
    await _arrivalSubscription?.cancel();
    _arrivalSubscription = null;
    _hasLeftSafeSpace = false;

    if (_session.isWatchingArrival) {
      _session = _session.copyWith(isWatchingArrival: false);
      await _persist();
    }
  }

  void _checkArrival(LocationFix fix) {
    if (_session.status != TimerSessionStatus.running) return;

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

    unawaited(
      _cancel().then((_) {
        FlutterForegroundTask.sendDataToMain({
          'event': 'arrived_during_countdown',
          'safeSpace': arrived.name,
        });
      }),
    );
  }

  /// The safe space the user is in at this moment, or null. Takes its own
  /// fresh fix rather than trusting the last one the stream delivered: with
  /// a ten metre movement filter, that reading can be minutes old and
  /// describe somewhere the user has since left.
  Future<SafeSpace?> _safeSpaceRightNow() async {
    if (_safeSpaces.isEmpty) return null;
    final fix = await _locationService.getFixForAlert();
    if (fix == null) return null;
    return _arrivalWatcher.arrivedAt(fix.point, fix.accuracy, _safeSpaces);
  }

  // --- The clock ---------------------------------------------------------

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_tick(timestamp));
  }

  Future<void> _tick(DateTime now) async {
    switch (_session.status) {
      case TimerSessionStatus.running:
        if (_session.isPastDeadline) await _handleDeadlineReached();
      case TimerSessionStatus.awaitingCheckIn:
        if (_session.isPastGraceDeadline(now)) await _dispatchAlert();
      case TimerSessionStatus.inactive:
      case TimerSessionStatus.paused:
      case TimerSessionStatus.expired:
        break;
    }
    _reportState();
  }

  /// The deadline just passed. Before alarming anyone: is the user
  /// demonstrably somewhere safe right now? If the phone can see them
  /// sitting inside a zone they told us is safe, that question is already
  /// answered, and texting contacts for help would be a false alarm about
  /// somebody at home.
  Future<void> _handleDeadlineReached() async {
    final arrived = await _safeSpaceRightNow();

    if (arrived != null) {
      await _cancel();
      FlutterForegroundTask.sendDataToMain({
        'event': 'timer_ended_but_safe',
        'safeSpace': arrived.name,
      });
      return;
    }

    _session = _session.copyWith(
      status: TimerSessionStatus.awaitingCheckIn,
      graceDeadline: DateTime.now().add(graceWindow),
    );
    await _persist();

    await FlutterForegroundTask.updateService(
      notificationTitle: 'Check in needed',
      notificationText: 'Tap "I\'m safe" or your contacts are alerted in '
          '${graceWindow.inSeconds}s.',
      notificationButtons: const [
        NotificationButton(id: 'checkin', text: "I'm safe"),
      ],
    );
  }

  Future<void> _dispatchAlert() async {
    final outcome = await _emergencyService.sendAlert(
      reason: AlertReason.timerExpired,
    );

    await _stopArrivalWatch();
    _session = _session.copyWith(
      status: TimerSessionStatus.expired,
      handledForDeadline: true,
      clearGraceDeadline: true,
    );
    await _persist();

    FlutterForegroundTask.sendDataToMain({
      'event': 'alert_sent',
      'summary': outcome.summary,
      'success': outcome.isSuccess,
    });

    await FlutterForegroundTask.updateService(
      notificationTitle:
          outcome.isSuccess ? 'SafeStep alert sent' : 'SafeStep alert failed',
      notificationText: outcome.summary,
      notificationButtons: const [],
    );
  }

  // --- Reporting back to the UI ----------------------------------------------

  Future<void> _persist() => _sessions.save(_session);

  void _reportState() {
    FlutterForegroundTask.sendDataToMain({
      'session': _session.toMap(),
      'nowMs': DateTime.now().millisecondsSinceEpoch,
    });

    // Only the plain countdown re-renders the notification every tick;
    // paused/awaitingCheckIn/expired set their own text at the moment they
    // start and don't need a once-a-second rewrite.
    if (_session.status == TimerSessionStatus.running) {
      final remaining = _session.remainingAt(DateTime.now());
      final arrivalNote =
          _session.isWatchingArrival ? ' - stops when you arrive' : '';
      FlutterForegroundTask.updateService(
        notificationTitle: 'Safety timer running',
        notificationText:
            'Checks in automatically in ${_formatDuration(remaining)}$arrivalNote',
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    return hours > 0 ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _arrivalSubscription?.cancel();
  }
}
