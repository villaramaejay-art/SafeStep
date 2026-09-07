import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:safe_step/services/emergency_service.dart';

/// The SMS body is the part of the alert a contact actually reads, and it
/// cannot be checked by sending real messages, so it is pinned down here.
void main() {
  final at = DateTime(2026, 9, 4, 17, 32);
  const manila = LatLng(14.60512, 120.98423);

  group('buildAlertMessage', () {
    test('a panic alert carries who, why, where and when', () {
      final message = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Dela Cruz',
        location: manila,
        accuracyMeters: 25,
        at: at,
      );

      expect(message, startsWith('SafeStep ALERT'));
      expect(message, contains('Maria Dela Cruz needs help.'));
      expect(message, contains('Reason: Panic button pressed'));
      expect(
        message,
        contains('https://maps.google.com/?q=14.60512,120.98423'),
      );
      expect(message, contains('(+/-25m)'));
      expect(message, contains('Time: 04/09/2026 5:32 PM'));
    });

    test('the timer alert names the missed check-in', () {
      final message = buildAlertMessage(
        reason: AlertReason.timerExpired,
        senderName: 'Maria Dela Cruz',
        location: manila,
        at: at,
      );

      expect(
        message,
        contains('Reason: Safety timer ended with no check-in'),
      );
    });

    test('an emergency is the only thing that says someone needs help', () {
      for (final reason in AlertReason.values.where((r) => r.isEmergency)) {
        expect(
          buildAlertMessage(
            reason: reason,
            senderName: 'Maria Dela Cruz',
            location: manila,
            at: at,
          ),
          contains('needs help'),
        );
      }
    });

    test('leaving a safe space is a notice, and never asks for help', () {
      final message = buildNoticeMessage(
        senderName: 'Maria Dela Cruz',
        safeSpaceName: 'Home',
        location: manila,
        at: at,
      );

      expect(message, startsWith('SafeStep UPDATE'));
      expect(message, contains('Maria Dela Cruz left "Home".'));
      // The whole point: a contact must be able to tell this from an alarm.
      expect(message, isNot(contains('needs help')));
      expect(message, isNot(contains('ALERT')));
    });

    test('a notice names the zone and stays whole', () {
      final message = buildNoticeMessage(
        senderName: 'Maria Dela Cruz',
        safeSpaceName: 'Lola Bunso House',
        location: manila,
        at: at,
      );

      expect(message, contains('left "Lola Bunso House".'));
      expect(message, contains('Time: 04/09/2026 5:32 PM'));
      expect(message, isNot(contains('null')));
    });

    test('a missing fix says so rather than sending empty coordinates', () {
      final message = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Dela Cruz',
        at: at,
      );

      expect(message, contains('Location: unavailable'));
      expect(message, isNot(contains('maps.google.com')));
      expect(message, isNot(contains('null')));
    });

    test('accuracy is omitted when it is unknown', () {
      final message = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Dela Cruz',
        location: manila,
        at: at,
      );

      expect(message, contains('maps.google.com'));
      expect(message, isNot(contains('+/-')));
    });

    test('midnight and noon do not both render as 0 or 12', () {
      String timeLineAt(DateTime when) => buildAlertMessage(
            reason: AlertReason.panic,
            senderName: 'A',
            at: when,
          ).split('\n').last;

      expect(timeLineAt(DateTime(2026, 1, 2, 0, 5)), contains('12:05 AM'));
      expect(timeLineAt(DateTime(2026, 1, 2, 12, 5)), contains('12:05 PM'));
      expect(timeLineAt(DateTime(2026, 1, 2, 13, 5)), contains('1:05 PM'));
    });
  });

  group('buildAllClearMessage', () {
    test('says the user is safe, and never that they need help', () {
      final message = buildAllClearMessage(
        senderName: 'Maria Dela Cruz',
        location: manila,
        at: at,
      );

      expect(message, startsWith('SafeStep ALL CLEAR'));
      expect(message, contains('Maria Dela Cruz is safe.'));
      expect(message, contains('stood down'));
      expect(message, isNot(contains('needs help')));
      expect(message, isNot(contains('ALERT')));
      expect(message, contains('Time: 04/09/2026 5:32 PM'));
    });

    test('carries where the user ended up when a fix is available', () {
      final message = buildAllClearMessage(
        senderName: 'Maria Dela Cruz',
        location: manila,
        at: at,
      );

      expect(
        message,
        contains('https://maps.google.com/?q=14.60512,120.98423'),
      );
    });

    test('drops the location line entirely when there is no fix', () {
      final message = buildAllClearMessage(
        senderName: 'Maria Dela Cruz',
        at: at,
      );

      // An alert says "Location: unavailable" because a contact needs to know
      // the gap; an all-clear has nothing to look for, so it stays silent.
      expect(message, isNot(contains('Location')));
      expect(message, contains('is safe.'));
    });

    test('the timestamp format matches the one an alert uses', () {
      final alert = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'A',
        at: at,
      );
      final allClear = buildAllClearMessage(senderName: 'A', at: at);

      expect(alert.split('\n').last, allClear.split('\n').last);
    });
  });

  group('the link-free fallback', () {
    test('a known place is named, so a contact can just go there', () {
      final plain = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Cruz',
        location: manila,
        accuracyMeters: 25,
        at: at,
        linkedMap: false,
        placeName: 'Rizal Avenue, Malate, Manila',
      );

      expect(plain, contains('Near: Rizal Avenue, Malate, Manila'));
      // The exact position rides along underneath, for whoever wants it.
      expect(plain, contains('Coords: 14.60512, 120.98423 (+/-25m)'));
      expect(plain, isNot(contains('http')));
    });

    test('an unknown place falls back to coordinates alone', () {
      final plain = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Cruz',
        location: manila,
        at: at,
        linkedMap: false,
      );

      expect(plain, contains('Location: 14.60512, 120.98423'));
      expect(plain, isNot(contains('Near:')));
    });

    test('an alert without the link carries plain coordinates', () {
      final plain = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Cruz',
        location: manila,
        accuracyMeters: 25,
        at: at,
        linkedMap: false,
      );

      expect(plain, contains('Location: 14.60512, 120.98423 (+/-25m)'));
      expect(plain, isNot(contains('http')));
      expect(plain, isNot(contains('maps.google.com')));
    });

    test('everything except the location line is unchanged', () {
      List<String> linesExceptLocation(bool linked) => buildAlertMessage(
            reason: AlertReason.panic,
            senderName: 'Maria Cruz',
            location: manila,
            accuracyMeters: 25,
            at: at,
            linkedMap: linked,
          ).split('\n').where((l) => !l.startsWith('Location:')).toList();

      expect(linesExceptLocation(false), linesExceptLocation(true));
    });

    test('the all-clear drops its link too', () {
      final plain = buildAllClearMessage(
        senderName: 'Maria Cruz',
        location: manila,
        at: at,
        linkedMap: false,
      );

      expect(plain, contains('Location: 14.60512, 120.98423'));
      expect(plain, isNot(contains('http')));
    });

    test('a link-free alert is shorter, so it never costs an extra message',
        () {
      String message(bool linked) => buildAlertMessage(
            reason: AlertReason.panic,
            senderName: 'Maria Cruz',
            location: manila,
            accuracyMeters: 25,
            at: at,
            linkedMap: linked,
          );

      expect(message(false).length, lessThan(message(true).length));
    });
  });

  group('smsAddress', () {
    test('hand-typed spacing and punctuation is stripped', () {
      expect(smsAddress('0932 292 0323'), '09322920323');
      expect(smsAddress('(0932) 292-0323'), '09322920323');
      expect(smsAddress(' 0932-292-0323 '), '09322920323');
    });

    test('a country code is kept, because the radio needs it', () {
      expect(smsAddress('+63 932 292 0323'), '+639322920323');
      expect(smsAddress('+63 (932) 292-0323'), '+639322920323');
    });

    test('a number that is already clean is left alone', () {
      expect(smsAddress('09322920323'), '09322920323');
      expect(smsAddress('+639322920323'), '+639322920323');
    });
  });

  group('SMS length', () {
    // Not a hard limit any more - sends are multipart - but every part past the
    // first costs the user another message, per contact.
    int parts(String message) => (message.length / 160).ceil();

    test('a typical panic alert costs one message', () {
      final message = buildAlertMessage(
        reason: AlertReason.panic,
        senderName: 'Maria Cruz',
        location: manila,
        accuracyMeters: 25,
        at: at,
      );

      expect(parts(message), 1, reason: message);
    });

    test('a typical all-clear costs one message', () {
      final message = buildAllClearMessage(
        senderName: 'Maria Cruz',
        location: manila,
        at: at,
      );

      expect(parts(message), 1, reason: message);
    });

    test('an unusually long name still sends, just as two parts', () {
      final message = buildNoticeMessage(
        senderName: 'Maria Antonieta Dela Cruz-Villaram',
        safeSpaceName: 'Lola Bunso House',
        location: manila,
        accuracyMeters: 1250,
        at: at,
      );

      expect(parts(message), lessThanOrEqualTo(2), reason: message);
    });
  });

  group('AlertReason', () {
    test('wire values match the schema CHECK constraint', () {
      expect(
        AlertReason.values.map((r) => r.wire).toList(),
        ['panic', 'timer_expired', 'left_safe_space', 'all_clear'],
      );
    });

    test('only a real emergency asks for help', () {
      expect(
        AlertReason.values.where((r) => r.isEmergency).toList(),
        [AlertReason.panic, AlertReason.timerExpired],
      );
    });

    test('each reason carries the tone its message is written in', () {
      expect(AlertReason.panic.tone, AlertTone.emergency);
      expect(AlertReason.timerExpired.tone, AlertTone.emergency);
      expect(AlertReason.leftSafeSpace.tone, AlertTone.notice);
      expect(AlertReason.allClear.tone, AlertTone.standDown);
    });

    test('every wire value round-trips', () {
      for (final reason in AlertReason.values) {
        expect(AlertReason.fromWire(reason.wire), reason);
      }
    });
  });

  group('cooldown', () {
    final now = DateTime(2026, 9, 4, 18, 0);

    test('a reason that has never fired is not cooling down', () {
      expect(EmergencyService.isWithinCooldown(null, now), isFalse);
    });

    test('a reason that just fired is blocked', () {
      final justNow = now.subtract(const Duration(seconds: 5));
      expect(EmergencyService.isWithinCooldown(justNow, now), isTrue);
    });

    test('the block lifts once the cooldown has elapsed', () {
      final old = now.subtract(EmergencyService.cooldown);
      expect(EmergencyService.isWithinCooldown(old, now), isFalse);
    });
  });

  group('AlertOutcome', () {
    test('each failure explains itself in a way a user can act on', () {
      const cases = {
        AlertProblem.unsupportedPlatform: 'only work on Android',
        AlertProblem.permissionDenied: 'SMS permission',
        AlertProblem.noContacts: 'Add an emergency contact',
      };

      cases.forEach((problem, fragment) {
        final outcome = AlertOutcome.failed(problem, null);
        expect(outcome.summary, contains(fragment));
        expect(outcome.isSuccess, isFalse);
      });
    });

    test('a partial send reports both numbers', () {
      const outcome = AlertOutcome(
        message: 'x',
        recipients: 3,
        delivered: 2,
      );

      expect(outcome.summary, 'Alert sent to 2 of 3 contacts.');
      expect(outcome.isSuccess, isTrue);
    });

    test('a full send reports just the count', () {
      const outcome = AlertOutcome(
        message: 'x',
        recipients: 2,
        delivered: 2,
      );

      expect(outcome.summary, 'Alert sent to 2 contacts.');
    });

    test('an all-clear is not announced as another alert', () {
      const outcome = AlertOutcome(
        message: 'x',
        recipients: 2,
        delivered: 2,
        reason: AlertReason.allClear,
      );

      expect(outcome.summary, 'All-clear sent to 2 contacts.');
      expect(outcome.summary, isNot(contains('Alert sent')));
    });
  });
}
