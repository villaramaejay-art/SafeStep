/// How loudly a message should read to whoever receives it.
///
/// The distinction matters more than it looks. A contact who is told somebody
/// "needs help" every time they walk out of a 200 m circle learns to ignore the
/// message - and it is the same message, on the same channel, that carries a
/// real emergency. Crying wolf is not a wording problem; it costs the alert its
/// meaning.
enum AlertTone {
  /// Something is wrong and the user wants help.
  emergency,

  /// Worth knowing, but nobody is asking for anything.
  notice,

  /// An earlier emergency is over.
  standDown,
}

/// Why an SMS went out. [wire] must match the `reason` CHECK constraint in
/// supabase/schema.sql.
enum AlertReason {
  panic('panic', 'Panic button', 'Panic button pressed', AlertTone.emergency),
  timerExpired(
    'timer_expired',
    'Timer expired',
    'Safety timer ended with no check-in',
    AlertTone.emergency,
  ),
  // A notice, not an alarm: leaving a zone says where somebody is, not that
  // anything has happened to them.
  leftSafeSpace(
    'left_safe_space',
    'Left safe space',
    'Left a safe space',
    AlertTone.notice,
  ),
  allClear('all_clear', 'All clear', 'Marked safe', AlertTone.standDown);

  const AlertReason(this.wire, this.label, this.description, this.tone);

  final String wire;

  /// Short heading for a history row.
  final String label;

  /// The sentence that goes into the SMS body.
  final String description;

  final AlertTone tone;

  /// True only when the message actually asks for help.
  bool get isEmergency => tone == AlertTone.emergency;

  /// Falls back to [panic] rather than throwing, so a schema that gained a
  /// reason this build does not know about still renders - and errs towards
  /// treating the unknown row as serious.
  static AlertReason fromWire(String value) {
    return AlertReason.values.firstWhere(
      (reason) => reason.wire == value,
      orElse: () => AlertReason.panic,
    );
  }
}

/// The timestamp format shared by the SMS body and the history list, so a
/// contact's message and the sender's record read the same.
String formatAlertTimestamp(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  final meridiem = when.hour < 12 ? 'AM' : 'PM';

  return '${when.day.toString().padLeft(2, '0')}/'
      '${when.month.toString().padLeft(2, '0')}/${when.year} '
      '$hour:$minute $meridiem';
}

/// How long ago something happened, in the shortest honest form.
String formatRelativeTime(DateTime when, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(when);

  if (elapsed.isNegative || elapsed.inSeconds < 60) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hr ago';
  }
  if (elapsed.inDays == 1) return 'Yesterday';
  if (elapsed.inDays < 7) return '${elapsed.inDays} days ago';

  return formatAlertTimestamp(when);
}

/// One row of the `alerts` table: an SMS that was actually attempted.
///
/// This is the record the user can point at afterwards - what was sent, to how
/// many people, from where, and when.
class AlertRecord {
  const AlertRecord({
    required this.id,
    required this.reason,
    required this.message,
    required this.recipients,
    required this.delivered,
    required this.createdAt,
    this.latitude,
    this.longitude,
    this.safeSpace,
    this.failure,
  });

  factory AlertRecord.fromMap(Map<String, dynamic> map) {
    return AlertRecord(
      id: map['id'] as String,
      reason: AlertReason.fromWire(map['reason'] as String),
      message: map['message'] as String,
      recipients: (map['recipients'] as num?)?.toInt() ?? 0,
      delivered: (map['delivered'] as num?)?.toInt() ?? 0,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      safeSpace: map['safe_space'] as String?,
      failure: map['failure'] as String?,
      // Postgres returns UTC; the history is read in the user's own time.
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final AlertReason reason;
  final String message;
  final int recipients;
  final int delivered;
  final double? latitude;
  final double? longitude;
  final String? safeSpace;

  /// What the network said when the send failed, if anything did. Null when
  /// the alert went out cleanly.
  final String? failure;
  final DateTime createdAt;

  bool get hasLocation => latitude != null && longitude != null;

  /// The same map link the recipients received, or null when the alert went out
  /// without a fix.
  String? get mapsLink {
    if (!hasLocation) return null;
    return 'https://maps.google.com/'
        '?q=${latitude!.toStringAsFixed(5)},${longitude!.toStringAsFixed(5)}';
  }

  /// Names the safe space when there is one, so two geofence alerts on the same
  /// day can be told apart.
  String get title {
    final space = safeSpace;
    if (reason == AlertReason.leftSafeSpace && space != null) {
      return 'Left "$space"';
    }
    return reason.label;
  }

  bool get reachedEveryone => recipients > 0 && delivered == recipients;

  String get deliverySummary {
    if (recipients == 0) return 'No contacts';
    if (delivered == 0) return 'Not delivered';
    return '$delivered of $recipients sent';
  }
}

/// Whether the contacts are still owed word that the user is safe.
///
/// True only while an emergency is the most recent thing that went out, and
/// only for [window] after it: past that the alert is old news, and a prompt
/// still sitting there would be nagging rather than helping.
///
/// Kept a pure function so the rule can be checked without a database.
bool needsAllClear(
  AlertRecord? latest, {
  required Duration window,
  DateTime? now,
}) {
  if (latest == null || !latest.reason.isEmergency) return false;
  return (now ?? DateTime.now()).difference(latest.createdAt) < window;
}
