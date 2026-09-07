import 'package:flutter_test/flutter_test.dart';
import 'package:safe_step/models/alert_record.dart';
import 'package:safe_step/models/contact.dart';
import 'package:safe_step/models/profile.dart';
import 'package:safe_step/models/safe_space.dart';

/// These guard the boundary with Postgres: column names and the `wire` values
/// must keep matching supabase/schema.sql, or reads and writes fail at runtime
/// in ways the analyzer cannot see.
void main() {
  group('ContactRelationship', () {
    test('wire values match the schema CHECK constraint', () {
      expect(
        ContactRelationship.values.map((r) => r.wire).toList(),
        ['father', 'mother', 'sister', 'spouse', 'friend', 'partner'],
      );
    });

    test('every wire value round-trips', () {
      for (final relationship in ContactRelationship.values) {
        expect(ContactRelationship.fromWire(relationship.wire), relationship);
      }
    });

    test('an unknown value falls back instead of throwing', () {
      expect(ContactRelationship.fromWire('cousin'), ContactRelationship.friend);
    });
  });

  group('ContactPriority', () {
    test('wire values match the schema CHECK constraint', () {
      expect(
        ContactPriority.values.map((p) => p.wire).toList(),
        ['primary', 'secondary'],
      );
    });

    test('anything that is not primary is treated as secondary', () {
      expect(ContactPriority.fromWire('primary'), ContactPriority.primary);
      expect(ContactPriority.fromWire('secondary'), ContactPriority.secondary);
      expect(ContactPriority.fromWire('nonsense'), ContactPriority.secondary);
    });
  });

  group('Contact', () {
    final row = <String, dynamic>{
      'id': '11111111-2222-3333-4444-555555555555',
      'user_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'full_name': 'Ana Reyes',
      'phone': '+63 917 123 4567',
      'relationship': 'sister',
      'priority': 'primary',
      'created_at': '2026-09-04T10:00:00Z',
    };

    test('fromMap reads every column the repository selects', () {
      final contact = Contact.fromMap(row);

      expect(contact.id, '11111111-2222-3333-4444-555555555555');
      expect(contact.fullName, 'Ana Reyes');
      expect(contact.phone, '+63 917 123 4567');
      expect(contact.relationship, ContactRelationship.sister);
      expect(contact.priority, ContactPriority.primary);
      expect(contact.isPrimary, isTrue);
    });

    test('toInsert emits wire values and leaves id to the database', () {
      final contact = Contact.fromMap(row);

      expect(contact.toInsert(), {
        'full_name': 'Ana Reyes',
        'phone': '+63 917 123 4567',
        'relationship': 'sister',
        'priority': 'primary',
      });
      expect(contact.toInsert().containsKey('id'), isFalse);
      expect(contact.toInsert().containsKey('user_id'), isFalse);
    });

    test('copyWith keeps the row id so updates target the right record', () {
      final updated = Contact.fromMap(row).copyWith(
        priority: ContactPriority.secondary,
      );

      expect(updated.id, row['id']);
      expect(updated.fullName, 'Ana Reyes');
      expect(updated.priority, ContactPriority.secondary);
    });
  });

  group('Profile', () {
    test('fromMap reads the registration columns', () {
      final profile = Profile.fromMap({
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'first_name': 'Maria',
        'last_name': 'Dela Cruz',
        'phone': '+63 917 000 1111',
        'created_at': '2026-09-04T10:00:00Z',
      });

      expect(profile.id, 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(profile.firstName, 'Maria');
      expect(profile.lastName, 'Dela Cruz');
      expect(profile.phone, '+63 917 000 1111');
      expect(profile.fullName, 'Maria Dela Cruz');
    });
  });

  group('SafeSpace', () {
    final row = <String, dynamic>{
      'id': '99999999-8888-7777-6666-555555555555',
      'name': 'Home',
      'latitude': 14.5995,
      'longitude': 120.9842,
      'radius_km': 3.0,
      'is_custom': false,
    };

    test('fromMap reads every column the repository selects', () {
      final space = SafeSpace.fromMap(row);

      expect(space.id, '99999999-8888-7777-6666-555555555555');
      expect(space.name, 'Home');
      expect(space.point.latitude, closeTo(14.5995, 1e-9));
      expect(space.point.longitude, closeTo(120.9842, 1e-9));
      expect(space.radius, 3.0);
      expect(space.isCustom, isFalse);
    });

    test('fromMap accepts integer coordinates from Postgres', () {
      final space = SafeSpace.fromMap({...row, 'latitude': 15, 'radius_km': 2});

      expect(space.point.latitude, 15.0);
      expect(space.radius, 2.0);
    });

    test('toInsert uses the schema column names', () {
      final space = SafeSpace.fromMap(row);

      expect(space.toInsert(), {
        'name': 'Home',
        'latitude': 14.5995,
        'longitude': 120.9842,
        'radius_km': 3.0,
        'is_custom': false,
      });
      expect(space.toInsert().containsKey('id'), isFalse);
    });
  });

  group('SafeSpace radius limits', () {
    test('the range matches the CHECK constraint in schema.sql', () {
      expect(SafeSpace.minRadiusKm, 0.1);
      expect(SafeSpace.maxRadiusKm, 0.5);
      expect(SafeSpace.defaultRadiusKm, inInclusiveRange(0.1, 0.5));
    });

    test('a radius reads in metres, because that is the scale now', () {
      expect(SafeSpace.formatRadius(0.1), '100 m');
      expect(SafeSpace.formatRadius(0.25), '250 m');
      expect(SafeSpace.formatRadius(0.5), '500 m');
    });

    test('a radius saved before the limits tightened is brought into range', () {
      // A Slider throws when handed a value outside its own bounds, so a 10 km
      // row from the old range would take the screen down without this.
      expect(SafeSpace.clampRadius(10), 0.5);
      expect(SafeSpace.clampRadius(1.5), 0.5);
      expect(SafeSpace.clampRadius(0.05), 0.1);
    });

    test('a radius already in range is left exactly alone', () {
      expect(SafeSpace.clampRadius(0.1), 0.1);
      expect(SafeSpace.clampRadius(0.3), 0.3);
      expect(SafeSpace.clampRadius(0.5), 0.5);
    });

    test('the slider steps in whole 50 m increments', () {
      final step =
          (SafeSpace.maxRadiusKm - SafeSpace.minRadiusKm) /
              SafeSpace.radiusDivisions;

      expect((step * 1000).round(), 50);
    });
  });

  group('AlertRecord', () {
    Map<String, dynamic> row({
      String reason = 'panic',
      double? latitude = 14.60512,
      double? longitude = 120.98423,
      String? safeSpace,
      int recipients = 2,
      int delivered = 2,
    }) {
      return {
        'id': 'a1',
        'reason': reason,
        'message': 'SafeStep ALERT\nMaria needs help.',
        'recipients': recipients,
        'delivered': delivered,
        'latitude': latitude,
        'longitude': longitude,
        'safe_space': safeSpace,
        'created_at': '2026-09-04T09:32:00Z',
      };
    }

    test('reads every column the alerts table writes', () {
      final alert = AlertRecord.fromMap(row());

      expect(alert.id, 'a1');
      expect(alert.reason, AlertReason.panic);
      expect(alert.message, contains('needs help'));
      expect(alert.recipients, 2);
      expect(alert.delivered, 2);
      expect(alert.latitude, 14.60512);
      expect(alert.longitude, 120.98423);
      expect(alert.safeSpace, isNull);
    });

    test('a timestamptz is converted to the reader local time', () {
      final alert = AlertRecord.fromMap(row());

      expect(alert.createdAt.isUtc, isFalse);
      expect(
        alert.createdAt.toUtc(),
        DateTime.utc(2026, 9, 4, 9, 32),
      );
    });

    test('an alert sent without a fix reports no location', () {
      final alert = AlertRecord.fromMap(
        row(latitude: null, longitude: null),
      );

      expect(alert.hasLocation, isFalse);
      expect(alert.mapsLink, isNull);
    });

    test('the map link matches the one that was texted', () {
      final alert = AlertRecord.fromMap(row());

      expect(alert.mapsLink, 'https://maps.google.com/?q=14.60512,120.98423');
    });

    test('a geofence alert names the space it left', () {
      final alert = AlertRecord.fromMap(
        row(reason: 'left_safe_space', safeSpace: 'Home'),
      );

      expect(alert.title, 'Left "Home"');
    });

    test('the other reasons fall back to their own label', () {
      expect(AlertRecord.fromMap(row()).title, 'Panic button');
      expect(
        AlertRecord.fromMap(row(reason: 'all_clear')).title,
        'All clear',
      );
    });

    test('delivery is reported honestly, including total failure', () {
      expect(AlertRecord.fromMap(row()).deliverySummary, '2 of 2 sent');
      expect(
        AlertRecord.fromMap(row(delivered: 1)).deliverySummary,
        '1 of 2 sent',
      );
      expect(
        AlertRecord.fromMap(row(delivered: 0)).deliverySummary,
        'Not delivered',
      );
      expect(
        AlertRecord.fromMap(row(recipients: 0, delivered: 0)).deliverySummary,
        'No contacts',
      );
      expect(AlertRecord.fromMap(row()).reachedEveryone, isTrue);
      expect(AlertRecord.fromMap(row(delivered: 1)).reachedEveryone, isFalse);
    });
  });

  group('formatRelativeTime', () {
    final now = DateTime(2026, 9, 4, 18, 0);

    String ago(Duration elapsed) =>
        formatRelativeTime(now.subtract(elapsed), now: now);

    test('recent times read as an elapsed span', () {
      expect(ago(const Duration(seconds: 20)), 'Just now');
      expect(ago(const Duration(minutes: 12)), '12 min ago');
      expect(ago(const Duration(hours: 3)), '3 hr ago');
      expect(ago(const Duration(days: 1)), 'Yesterday');
      expect(ago(const Duration(days: 3)), '3 days ago');
    });

    test('anything older than a week shows the actual date', () {
      expect(ago(const Duration(days: 9)), '26/08/2026 6:00 PM');
    });

    test('a clock skewed into the future does not print a negative span', () {
      expect(ago(const Duration(minutes: -5)), 'Just now');
    });
  });

  group('needsAllClear', () {
    final now = DateTime(2026, 9, 4, 18, 0);
    const window = Duration(hours: 12);

    AlertRecord sent(AlertReason reason, Duration ago) => AlertRecord(
          id: 'a1',
          reason: reason,
          message: 'x',
          recipients: 1,
          delivered: 1,
          createdAt: now.subtract(ago),
        );

    bool owed(AlertRecord? latest) =>
        needsAllClear(latest, window: window, now: now);

    test('an account that never sent anything is owed nothing', () {
      expect(owed(null), isFalse);
    });

    test('a recent emergency leaves the loop open', () {
      expect(owed(sent(AlertReason.panic, const Duration(minutes: 10))), isTrue);
      expect(owed(sent(AlertReason.timerExpired, const Duration(hours: 2))),
          isTrue);
    });

    test('leaving a safe space owes nobody an all-clear', () {
      // Nothing was raised: the contacts were told where the user went, not
      // that anything was wrong. There is no alarm to stand down.
      expect(
        owed(sent(AlertReason.leftSafeSpace, const Duration(minutes: 5))),
        isFalse,
      );
    });

    test('an all-clear closes the loop', () {
      expect(
        owed(sent(AlertReason.allClear, const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('the prompt stops nagging once the window has passed', () {
      expect(owed(sent(AlertReason.panic, window)), isFalse);
      expect(owed(sent(AlertReason.panic, const Duration(days: 2))), isFalse);
    });
  });
}
