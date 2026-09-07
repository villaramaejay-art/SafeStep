import 'package:latlong2/latlong.dart';

import '../models/safe_space.dart';

/// Decides whether a position counts as having reached one of the user's safe
/// spaces.
///
/// Kept a pure class with no timer, stream or plugin, so the rule that disarms
/// a safety timer can be checked directly.
///
/// The test is deliberately stricter than the one that fires an exit alert, and
/// the asymmetry is the point:
///
/// * Leaving asks "is the whole accuracy circle outside?" before raising an
///   alarm, so noise cannot cry wolf.
/// * Arriving asks "is the whole accuracy circle inside?" before standing a
///   timer down, so noise cannot quietly disarm the one thing watching for the
///   user.
///
/// A false alarm is noisy. A timer wrongly cancelled is silent, and silence is
/// what this feature exists to prevent.
class ArrivalWatcher {
  const ArrivalWatcher({Distance distance = const Distance()})
      : _distance = distance;

  final Distance _distance;

  /// The safe space [position] has certainly reached, or null.
  ///
  /// [accuracyMeters] is the fix's own error radius. Nearest space wins when
  /// two overlap, so the message names the one the user is actually at.
  SafeSpace? arrivedAt(
    LatLng position,
    double accuracyMeters,
    List<SafeSpace> spaces,
  ) {
    SafeSpace? closest;
    var closestMeters = double.infinity;

    for (final space in spaces) {
      final meters = _distance.as(LengthUnit.Meter, position, space.point);
      final radiusMeters = space.radius * 1000;

      // Every point the fix could actually be must fall inside the zone.
      if (meters + accuracyMeters > radiusMeters) continue;

      if (meters < closestMeters) {
        closest = space;
        closestMeters = meters;
      }
    }

    return closest;
  }
}
