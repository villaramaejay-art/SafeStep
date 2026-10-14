import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/alert_record.dart';

/// Persisted, cross-isolate backing for [EmergencyService]'s cooldown and
/// carrier-link learning.
///
/// These used to be bare static fields on `EmergencyService` - fine as long
/// as exactly one Dart isolate ever ran the app. Once the Safety Timer can
/// fire from a background foreground-service isolate that never shared
/// memory with the UI isolate, an in-memory-only cooldown stops meaning
/// anything: each isolate would have its own answer to "did this already
/// fire in the last 60 seconds?" This keeps the same synchronous read API
/// `EmergencyService` already had (nothing calling `isCoolingDown` needs to
/// change) by caching in memory and requiring [hydrate] to fill that cache
/// from disk once per isolate; every write updates both the cache and disk.
class AlertCooldownStore {
  const AlertCooldownStore._();

  static const _lastSentKeyPrefix = 'alert_cooldown_last_sent_';
  static const _carrierStripsLinksKey = 'alert_cooldown_carrier_strips_links';

  static final Map<AlertReason, DateTime> _lastSentAt = {};
  static bool _carrierStripsLinks = false;
  static bool _hydrated = false;

  /// Loads persisted state into the in-memory cache this isolate reads from.
  /// Call once per isolate - at app start for the UI isolate, at task start
  /// for the background isolate - before trusting [lastSentAt] or
  /// [carrierStripsLinks]. A second call is a cheap no-op.
  static Future<void> hydrate() async {
    if (_hydrated) return;

    final prefs = await SharedPreferences.getInstance();
    for (final reason in AlertReason.values) {
      final millis = prefs.getInt('$_lastSentKeyPrefix${reason.wire}');
      if (millis != null) {
        _lastSentAt[reason] = DateTime.fromMillisecondsSinceEpoch(millis);
      }
    }
    _carrierStripsLinks = prefs.getBool(_carrierStripsLinksKey) ?? false;
    _hydrated = true;
  }

  static DateTime? lastSentAt(AlertReason reason) => _lastSentAt[reason];

  /// Records that [reason] fired at [when], readable synchronously from this
  /// isolate immediately, and from any isolate after its next [hydrate].
  static void recordSent(AlertReason reason, DateTime when) {
    _lastSentAt[reason] = when;
    unawaited(_persistLastSent(reason, when));
  }

  static Future<void> _persistLastSent(AlertReason reason, DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      '$_lastSentKeyPrefix${reason.wire}',
      when.millisecondsSinceEpoch,
    );
  }

  static bool get carrierStripsLinks => _carrierStripsLinks;

  static set carrierStripsLinks(bool value) {
    _carrierStripsLinks = value;
    unawaited(_persistCarrierFlag(value));
  }

  static Future<void> _persistCarrierFlag(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_carrierStripsLinksKey, value);
  }

  /// Test/debug only: drops the cache and disk state for every reason.
  static void reset() {
    _lastSentAt.clear();
    _carrierStripsLinks = false;
    unawaited(_clearPersisted());
  }

  static Future<void> _clearPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    for (final reason in AlertReason.values) {
      await prefs.remove('$_lastSentKeyPrefix${reason.wire}');
    }
    await prefs.remove(_carrierStripsLinksKey);
  }
}
