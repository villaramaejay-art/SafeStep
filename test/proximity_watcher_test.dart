import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:safe_step/models/help_place.dart';
import 'package:safe_step/services/proximity_alerts.dart';

/// These pin down how often the user is interrupted, which is the whole risk of
/// this feature: a station 700 m from home would otherwise announce itself
/// every time its owner walked to the shops.
void main() {
  const origin = LatLng(15.07128, 120.94094);
  const distance = Distance();

  // Distances are written against the configured radius rather than a literal,
  // so retuning it cannot leave these tests quietly checking the wrong thing.
  const radius = ProximityWatcher.defaultRadiusMeters;
  const margin = ProximityWatcher.exitMarginMeters;

  /// A point [meters] due east of [origin], so tests can name a distance
  /// instead of a coordinate.
  LatLng east(double meters) =>
      distance.offset(origin, meters, 90);

  const station = HelpPlace(
    id: 'node/1',
    kind: HelpPlaceKind.police,
    point: origin,
    name: 'San Ildefonso Police Station',
  );

  const fireStation = HelpPlace(
    id: 'node/2',
    kind: HelpPlaceKind.fireStation,
    point: LatLng(15.08128, 120.94094),
    name: 'San Ildefonso Fire Station',
  );

  group('ProximityWatcher', () {
    test('coming into range reports the station once', () {
      final watcher = ProximityWatcher();

      final first = watcher.evaluate(east(radius * 0.6), [station]);
      expect(first, hasLength(1));
      expect(first.single.place.id, station.id);
      expect(first.single.meters, closeTo(radius * 0.6, 5));
    });

    test('staying in range does not keep announcing it', () {
      final watcher = ProximityWatcher();

      expect(watcher.evaluate(east(radius * 0.6), [station]), hasLength(1));
      expect(watcher.evaluate(east(radius * 0.5), [station]), isEmpty);
      expect(watcher.evaluate(east(radius * 0.2), [station]), isEmpty);
      expect(watcher.evaluate(east(radius * 0.9), [station]), isEmpty);
    });

    test('a fix outside the range reports nothing', () {
      final watcher = ProximityWatcher();

      expect(watcher.evaluate(east(radius + margin * 2), [station]), isEmpty);
    });

    test('it announces again only after a real departure', () {
      final watcher = ProximityWatcher();

      expect(watcher.evaluate(east(radius * 0.6), [station]), hasLength(1));

      // Past the radius but still inside the margin: not yet a departure, so
      // stepping back in must stay quiet.
      expect(watcher.evaluate(east(radius + margin * 0.5), [station]), isEmpty);
      expect(watcher.evaluate(east(radius * 0.6), [station]), isEmpty);

      // Clearly gone, then back.
      expect(watcher.evaluate(east(radius + margin * 2), [station]), isEmpty);
      expect(watcher.evaluate(east(radius * 0.6), [station]), hasLength(1));
    });

    test('a fix wobbling across the boundary does not flap', () {
      final watcher = ProximityWatcher();
      expect(watcher.evaluate(east(radius * 0.6), [station]), hasLength(1));

      // GPS noise either side of the boundary must not re-announce.
      for (final meters in [
        radius * 0.96,
        radius * 1.04,
        radius * 0.99,
        radius * 1.08,
        radius * 1.01,
        radius * 0.94,
      ]) {
        expect(
          watcher.evaluate(east(meters), [station]),
          isEmpty,
          reason: 'wobble at $meters m re-announced',
        );
      }
    });

    test('each station is tracked on its own', () {
      final watcher = ProximityWatcher();

      // Only the police station is in range at the origin.
      final first = watcher.evaluate(origin, [station, fireStation]);
      expect(first.map((h) => h.place.id), [station.id]);

      // Moving to the fire station reports it, and does not repeat the police
      // one even though it is now out of range and back is possible.
      final second = watcher.evaluate(fireStation.point, [station, fireStation]);
      expect(second.map((h) => h.place.id), [fireStation.id]);
    });

    test('reset makes the next reading fresh again', () {
      final watcher = ProximityWatcher();

      expect(watcher.evaluate(east(radius * 0.6), [station]), hasLength(1));
      expect(watcher.evaluate(east(radius * 0.6), [station]), isEmpty);

      watcher.reset();
      expect(watcher.evaluate(east(radius * 0.6), [station]), hasLength(1));
    });

    test('no stations means nothing to report', () {
      expect(ProximityWatcher().evaluate(origin, const []), isEmpty);
    });

    test('a tighter radius can be asked for', () {
      final watcher = ProximityWatcher(radiusMeters: 40);

      // Inside the default ring, but outside this one.
      expect(watcher.evaluate(east(radius * 0.6), [station]), isEmpty);
      expect(watcher.evaluate(east(25), [station]), hasLength(1));
    });

    test('the shipped radius is the tight one a town needs', () {
      // The whole point of the retune: a station a few hundred metres away must
      // not announce itself, or the alert becomes part of the daily commute.
      expect(radius, 100);
      expect(
        ProximityWatcher().evaluate(east(250), [station]),
        isEmpty,
        reason: 'a station 250 m away should stay quiet',
      );
    });
  });

  group('HelpPlace', () {
    test('a mapped name is used', () {
      expect(station.label, 'San Ildefonso Police Station');
    });

    test('a station mapped without a name still identifies itself', () {
      const unnamed = HelpPlace(
        id: 'node/3',
        kind: HelpPlaceKind.fireStation,
        point: origin,
      );

      expect(unnamed.label, 'Fire station');
    });

    test('a blank name is treated as no name', () {
      const blank = HelpPlace(
        id: 'node/4',
        kind: HelpPlaceKind.police,
        point: origin,
        name: '   ',
      );

      expect(blank.label, 'Police station');
    });

    test('the OSM tags match what Overpass is queried for', () {
      expect(
        HelpPlaceKind.values.map((k) => k.tag).toList(),
        ['police', 'fire_station'],
      );
      expect(HelpPlaceKind.fromTag('police'), HelpPlaceKind.police);
      expect(HelpPlaceKind.fromTag('fire_station'), HelpPlaceKind.fireStation);
      expect(HelpPlaceKind.fromTag('hospital'), isNull);
    });
  });
}
