import 'package:shared_preferences/shared_preferences.dart';

/// Where the Safety Timer's own countdown currently stands. Kept distinct
/// from a plain "is it running" bool because the recovery logic after a
/// process restart needs to tell a timer that's still counting down apart
/// from one that already fired while nothing was alive to see it happen.
enum TimerSessionStatus {
  inactive,
  running,
  paused,
  awaitingCheckIn,
  expired;

  static TimerSessionStatus fromName(String? name) {
    return TimerSessionStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => TimerSessionStatus.inactive,
    );
  }
}

/// A snapshot of the Safety Timer, persisted so it survives the Dart isolate
/// that was running it being killed and restarted - by the OS, by the user
/// locking the screen, or by the foreground service itself relaunching.
class TimerSession {
  const TimerSession({
    required this.status,
    this.deadline,
    this.selectedMinutes,
    this.handledForDeadline = false,
    this.pausedRemainingMs,
    this.graceDeadline,
    this.isWatchingArrival = false,
  });

  static const TimerSession inactive = TimerSession(
    status: TimerSessionStatus.inactive,
  );

  final TimerSessionStatus status;

  /// When the countdown reaches zero. Null when [status] is inactive or
  /// paused - a paused timer isn't counting down against any clock time
  /// until it resumes.
  final DateTime? deadline;

  /// The duration the user picked, so a resumed/restarted timer can still
  /// show "10 minutes" rather than just a bare countdown.
  final int? selectedMinutes;

  /// True once the expiry for [deadline] has already been acted on (safe-space
  /// check run, grace period offered, alert sent or stood down). Stops a
  /// process that restarts after the deadline already passed from running
  /// that whole flow - and potentially sending a second alert - again.
  final bool handledForDeadline;

  /// How much time was left when the timer was paused. Only meaningful while
  /// [status] is [TimerSessionStatus.paused]; resuming turns this back into a
  /// fresh [deadline] of `now + pausedRemainingMs`.
  final int? pausedRemainingMs;

  /// While [status] is [TimerSessionStatus.awaitingCheckIn], the moment the
  /// grace period itself runs out and the alert actually sends.
  final DateTime? graceDeadline;

  /// Whether the "arrived at a safe space disarms the timer" watch is
  /// currently live - purely informational for the UI's status line.
  final bool isWatchingArrival;

  bool get isPastDeadline {
    final value = deadline;
    if (value == null) return false;
    return !value.isAfter(DateTime.now());
  }

  bool isPastGraceDeadline(DateTime now) {
    final value = graceDeadline;
    if (value == null) return false;
    return !value.isAfter(now);
  }

  Duration remainingAt(DateTime now) {
    final value = deadline;
    if (value == null) return Duration.zero;
    final diff = value.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  Duration graceRemainingAt(DateTime now) {
    final value = graceDeadline;
    if (value == null) return Duration.zero;
    final diff = value.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  TimerSession copyWith({
    TimerSessionStatus? status,
    DateTime? deadline,
    bool clearDeadline = false,
    int? selectedMinutes,
    bool? handledForDeadline,
    int? pausedRemainingMs,
    bool clearPausedRemainingMs = false,
    DateTime? graceDeadline,
    bool clearGraceDeadline = false,
    bool? isWatchingArrival,
  }) {
    return TimerSession(
      status: status ?? this.status,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      selectedMinutes: selectedMinutes ?? this.selectedMinutes,
      handledForDeadline: handledForDeadline ?? this.handledForDeadline,
      pausedRemainingMs: clearPausedRemainingMs
          ? null
          : (pausedRemainingMs ?? this.pausedRemainingMs),
      graceDeadline:
          clearGraceDeadline ? null : (graceDeadline ?? this.graceDeadline),
      isWatchingArrival: isWatchingArrival ?? this.isWatchingArrival,
    );
  }

  Map<String, dynamic> toMap() => {
        'status': status.name,
        'deadlineMs': deadline?.millisecondsSinceEpoch,
        'selectedMinutes': selectedMinutes,
        'handledForDeadline': handledForDeadline,
        'pausedRemainingMs': pausedRemainingMs,
        'graceDeadlineMs': graceDeadline?.millisecondsSinceEpoch,
        'isWatchingArrival': isWatchingArrival,
      };

  static TimerSession fromMap(Map<dynamic, dynamic> map) {
    final deadlineMs = map['deadlineMs'] as int?;
    final graceMs = map['graceDeadlineMs'] as int?;
    return TimerSession(
      status: TimerSessionStatus.fromName(map['status'] as String?),
      deadline: deadlineMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deadlineMs),
      selectedMinutes: map['selectedMinutes'] as int?,
      handledForDeadline: map['handledForDeadline'] as bool? ?? false,
      pausedRemainingMs: map['pausedRemainingMs'] as int?,
      graceDeadline:
          graceMs == null ? null : DateTime.fromMillisecondsSinceEpoch(graceMs),
      isWatchingArrival: map['isWatchingArrival'] as bool? ?? false,
    );
  }
}

/// Reads and writes the one active [TimerSession] to local, per-device
/// storage. There is only ever one timer, so this holds a single record
/// rather than a list - unlike `ContactsRepository`/`SafeSpacesRepository`,
/// which hold the user's whole collection in Supabase.
class TimerSessionRepository {
  static const _keyStatus = 'timer_session_status';
  static const _keyDeadlineMs = 'timer_session_deadline_ms';
  static const _keySelectedMinutes = 'timer_session_selected_minutes';
  static const _keyHandled = 'timer_session_handled_for_deadline';
  static const _keyPausedRemainingMs = 'timer_session_paused_remaining_ms';
  static const _keyGraceDeadlineMs = 'timer_session_grace_deadline_ms';
  static const _keyIsWatchingArrival = 'timer_session_is_watching_arrival';

  Future<TimerSession> load() async {
    final prefs = await SharedPreferences.getInstance();

    final deadlineMs = prefs.getInt(_keyDeadlineMs);
    final graceMs = prefs.getInt(_keyGraceDeadlineMs);
    return TimerSession(
      status: TimerSessionStatus.fromName(prefs.getString(_keyStatus)),
      deadline: deadlineMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deadlineMs),
      selectedMinutes: prefs.getInt(_keySelectedMinutes),
      handledForDeadline: prefs.getBool(_keyHandled) ?? false,
      pausedRemainingMs: prefs.getInt(_keyPausedRemainingMs),
      graceDeadline:
          graceMs == null ? null : DateTime.fromMillisecondsSinceEpoch(graceMs),
      isWatchingArrival: prefs.getBool(_keyIsWatchingArrival) ?? false,
    );
  }

  Future<void> save(TimerSession session) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_keyStatus, session.status.name);

    final deadline = session.deadline;
    if (deadline == null) {
      await prefs.remove(_keyDeadlineMs);
    } else {
      await prefs.setInt(_keyDeadlineMs, deadline.millisecondsSinceEpoch);
    }

    final minutes = session.selectedMinutes;
    if (minutes != null) {
      await prefs.setInt(_keySelectedMinutes, minutes);
    }

    await prefs.setBool(_keyHandled, session.handledForDeadline);

    final pausedRemaining = session.pausedRemainingMs;
    if (pausedRemaining == null) {
      await prefs.remove(_keyPausedRemainingMs);
    } else {
      await prefs.setInt(_keyPausedRemainingMs, pausedRemaining);
    }

    final graceDeadline = session.graceDeadline;
    if (graceDeadline == null) {
      await prefs.remove(_keyGraceDeadlineMs);
    } else {
      await prefs.setInt(_keyGraceDeadlineMs, graceDeadline.millisecondsSinceEpoch);
    }

    await prefs.setBool(_keyIsWatchingArrival, session.isWatchingArrival);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyStatus);
    await prefs.remove(_keyDeadlineMs);
    await prefs.remove(_keySelectedMinutes);
    await prefs.remove(_keyHandled);
    await prefs.remove(_keyPausedRemainingMs);
    await prefs.remove(_keyGraceDeadlineMs);
    await prefs.remove(_keyIsWatchingArrival);
  }
}
