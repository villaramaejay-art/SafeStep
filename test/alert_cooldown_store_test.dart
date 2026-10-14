import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safe_step/services/alert_cooldown_store.dart';
import 'package:safe_step/services/emergency_service.dart';

void main() {
  // AlertCooldownStore.hydrate() is deliberately idempotent - it loads from
  // disk only the first time it's ever called in a given isolate, the same
  // way it only runs once in each real isolate the app starts (see
  // lib/main.dart and safety_task_handler.dart). All tests below therefore
  // share one hydration, exactly like the app does - they don't re-hydrate
  // between tests, only read/write through AlertCooldownStore's own API or
  // SharedPreferences directly to see what actually reached disk.

  test('hydrate seeds the cache from whatever was already on disk', () async {
    final persistedSend = DateTime(2026, 2, 1, 8).millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'alert_cooldown_last_sent_${AlertReason.panic.wire}': persistedSend,
      'alert_cooldown_carrier_strips_links': true,
    });

    await AlertCooldownStore.hydrate();

    expect(
      AlertCooldownStore.lastSentAt(AlertReason.panic),
      DateTime.fromMillisecondsSinceEpoch(persistedSend),
    );
    expect(AlertCooldownStore.carrierStripsLinks, isTrue);
  });

  test('recordSent is readable synchronously and writes through to disk', () async {
    final now = DateTime.now();
    AlertCooldownStore.recordSent(AlertReason.timerExpired, now);

    // Synchronous: no await needed to read what was just recorded.
    expect(AlertCooldownStore.lastSentAt(AlertReason.timerExpired), now);

    // Give the fire-and-forget disk write a turn to land, then confirm a
    // fresh read of SharedPreferences (not the in-memory cache) sees it -
    // this is what a different isolate's own hydrate() would read.
    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt('alert_cooldown_last_sent_${AlertReason.timerExpired.wire}'),
      now.millisecondsSinceEpoch,
    );
  });

  test('carrierStripsLinks setter writes through to disk', () async {
    AlertCooldownStore.carrierStripsLinks = true;
    expect(AlertCooldownStore.carrierStripsLinks, isTrue);

    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('alert_cooldown_carrier_strips_links'), isTrue);
  });

  test('reset clears both the cache and disk for every reason', () async {
    AlertCooldownStore.recordSent(AlertReason.leftSafeSpace, DateTime.now());
    AlertCooldownStore.carrierStripsLinks = true;

    AlertCooldownStore.reset();

    expect(AlertCooldownStore.lastSentAt(AlertReason.leftSafeSpace), isNull);
    expect(AlertCooldownStore.carrierStripsLinks, isFalse);

    await Future<void>.delayed(Duration.zero);
    final prefs = await SharedPreferences.getInstance();
    for (final reason in AlertReason.values) {
      expect(prefs.getInt('alert_cooldown_last_sent_${reason.wire}'), isNull);
    }
    expect(prefs.getBool('alert_cooldown_carrier_strips_links'), isNull);
  });

  test('EmergencyService.isCoolingDown reflects what was persisted here', () {
    final now = DateTime.now();
    AlertCooldownStore.recordSent(AlertReason.panic, now);

    final stillCoolingDown = now.add(const Duration(seconds: 30));
    final cooldownOver = now.add(EmergencyService.cooldown * 2);

    expect(
      EmergencyService.isCoolingDown(AlertReason.panic, now: stillCoolingDown),
      isTrue,
    );
    expect(
      EmergencyService.isCoolingDown(AlertReason.panic, now: cooldownOver),
      isFalse,
    );
  });
}
