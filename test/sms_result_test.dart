import 'package:flutter_test/flutter_test.dart';
import 'package:safe_step/services/sms_sender.dart';

/// The whole point of the app's own SMS channel is that a refused message is
/// reported as refused. These pin the wording the user is shown, because on a
/// prepaid phone that sentence is the difference between "the app is broken"
/// and "top up your load".
void main() {
  group('SmsResult', () {
    test('a send the network accepted is the only success', () {
      const sent = SmsResult(ok: true, code: 0);

      expect(sent.ok, isTrue);
      expect(sent.reason, 'Sent');
    });

    test('a generic failure points at the likeliest cause', () {
      const refused = SmsResult(ok: false, code: 1);

      expect(refused.reason, contains('load'));
    });

    test('the conditions a user can actually fix are named', () {
      expect(const SmsResult(ok: false, code: 2).reason, contains('airplane'));
      expect(const SmsResult(ok: false, code: 4).reason, contains('No mobile'));
      expect(
        const SmsResult(ok: false, code: 6).reason,
        contains('fixed dialling'),
      );
    });

    test('silence is reported as silence, not as success or failure', () {
      const quiet = SmsResult(ok: false, code: -1, timedOut: true);

      expect(quiet.reason, contains('never confirmed'));
      expect(quiet.reason, contains('may still be queued'));
    });

    test('a platform failure carries its own message through', () {
      const broken = SmsResult.failure('SmsManager was null');

      expect(broken.ok, isFalse);
      expect(broken.reason, 'SmsManager was null');
    });

    test('an unknown code still says something useful', () {
      const odd = SmsResult(ok: false, code: 27);

      expect(odd.reason, contains('27'));
      expect(odd.reason, contains('no load'));
    });
  });

  group('SimCard', () {
    test('reads what the platform reports', () {
      final sim = SimCard.fromMap(const {
        'subscriptionId': 3,
        'label': 'Smart',
        'slot': 1,
      });

      expect(sim.subscriptionId, 3);
      expect(sim.label, 'Smart');
      expect(sim.slot, 1);
    });

    test('a SIM with no name still gets one', () {
      final sim = SimCard.fromMap(const {'subscriptionId': 1});

      expect(sim.label, 'SIM');
      expect(sim.subscriptionId, 1);
    });
  });
}
