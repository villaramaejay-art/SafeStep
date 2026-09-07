import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:safe_step/models/safe_space.dart';
import 'package:safe_step/services/arrival_watcher.dart';

/// This rule switches off the one thing watching for the user, so it is held to
/// a higher bar than the rule that raises an alarm. A wrong alert is noisy; a
/// wrongly cancelled timer is silent, and nobody finds out until it matters.
void main() {
  const home = LatLng(15.07128, 120.94094);
  const distance = Distance();

  LatLng metresAway(double metres) => distance.offset(home, metres, 90);

  SafeSpace space(String name, LatLng point, double radiusKm) => SafeSpace(
        id: name,
        name: name,
        point: point,
        radius: radiusKm,
      );

  // 300 m radius: mid-range for what the app now allows.
  final homeZone = space('Homie', home, 0.3);
  const watcher = ArrivalWatcher();

  group('ArrivalWatcher', () {
    test('a fix well inside counts as arrived', () {
      expect(
        watcher.arrivedAt(metresAway(50), 15, [homeZone])?.name,
        'Homie',
      );
    });

    test('a fix outside the zone is not an arrival', () {
      expect(watcher.arrivedAt(metresAway(400), 15, [homeZone]), isNull);
    });

    test('a fix inside but within its own error of the edge does not count',
        () {
      // 290 m from the centre of a 300 m zone, but accurate only to 40 m: the
      // user could genuinely be 30 m outside. Not good enough to disarm.
      expect(watcher.arrivedAt(metresAway(290), 40, [homeZone]), isNull);
    });

    test('the same spot counts once the fix sharpens', () {
      expect(watcher.arrivedAt(metresAway(290), 40, [homeZone]), isNull);
      expect(
        watcher.arrivedAt(metresAway(290), 5, [homeZone])?.name,
        'Homie',
      );
    });

    test('a wildly inaccurate fix never counts, wherever it claims to be', () {
      // A 500 m error circle cannot be proven to sit inside a 300 m zone, even
      // dead on the centre.
      expect(watcher.arrivedAt(home, 500, [homeZone]), isNull);
    });

    test('no safe spaces means nothing to arrive at', () {
      expect(watcher.arrivedAt(home, 10, const []), isNull);
    });

    test('the nearest zone is named when two overlap', () {
      final nearby = space('Lola', metresAway(60), 0.3);

      // Sitting 10 m from home, inside both.
      final arrived = watcher.arrivedAt(metresAway(10), 5, [nearby, homeZone]);

      expect(arrived?.name, 'Homie');
    });

    test('any saved zone will do, not just the first', () {
      final far = space('Eskwela', distance.offset(home, 5000, 90), 0.3);

      expect(
        watcher.arrivedAt(far.point, 10, [homeZone, far])?.name,
        'Eskwela',
      );
    });

    test('a tight zone still works with a sharp fix', () {
      final tight = space('Tindahan', home, SafeSpace.minRadiusKm);

      expect(watcher.arrivedAt(metresAway(60), 20, [tight])?.name, 'Tindahan');
      expect(watcher.arrivedAt(metresAway(90), 20, [tight]), isNull);
    });
  });
}
