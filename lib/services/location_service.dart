import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// A single point-in-time GPS reading.
class LocationFix {
  const LocationFix({
    required this.point,
    required this.accuracy,
    required this.timestamp,
  });

  final LatLng point;

  /// Radius of uncertainty around [point], in meters.
  final double accuracy;

  final DateTime timestamp;
}

/// Why a location request could not be completed.
enum LocationFailure {
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  timedOut,
}

class LocationException implements Exception {
  const LocationException(this.failure, this.message);

  final LocationFailure failure;

  /// Message that is safe to show directly in the UI.
  final String message;

  @override
  String toString() => 'LocationException($failure): $message';
}

/// Wraps `geolocator` so screens only deal with [LatLng] and [LocationException].
class LocationService {
  static const Distance _distance = Distance();

  static const LocationSettings _oneShotSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 20),
  );

  static const LocationSettings _streamSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  /// Throws a [LocationException] unless location is enabled and granted.
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        LocationFailure.serviceDisabled,
        'Turn on location services to use live tracking.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationFailure.permissionDeniedForever,
        'Location is blocked for SafeStep. Enable it in device settings.',
      );
    }

    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationFailure.permissionDenied,
        'SafeStep needs location permission to show where you are.',
      );
    }
  }

  /// One-shot fix. Falls back to the last known position on timeout.
  Future<LocationFix> getCurrentFix() async {
    await ensurePermission();

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: _oneShotSettings,
      );
      return _fixFrom(position);
    } on TimeoutException {
      final lastKnown = await Geolocator.getLastKnownPosition();

      if (lastKnown != null) return _fixFrom(lastKnown);

      throw const LocationException(
        LocationFailure.timedOut,
        'Could not get a GPS fix in time. Try again in an open area.',
      );
    }
  }

  /// How long an alert will wait for a position before giving up on a fresh one.
  ///
  /// Deliberately far shorter than [_oneShotSettings]: a panic alert that sits
  /// silent for twenty seconds reads as a broken button, and the user has no
  /// way to tell waiting from failure.
  static const Duration alertDeadline = Duration(seconds: 5);

  /// The fix to attach to an alert that is already going out.
  ///
  /// Never throws and never blocks for long. Medium accuracy resolves from the
  /// network in about a second where high accuracy waits on satellites, and the
  /// last known position is used the moment the deadline passes.
  ///
  /// A location from a few minutes ago, sent now, is worth more to somebody
  /// coming to help than an exact one sent a minute late - or none at all.
  Future<LocationFix?> getFixForAlert() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: alertDeadline,
        ),
      ).timeout(alertDeadline);

      return _fixFrom(position);
    } catch (_) {
      // Any failure at all - timeout, permission, no provider - falls through
      // to whatever the device already knows.
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition()
          .timeout(const Duration(seconds: 2));

      return lastKnown == null ? null : _fixFrom(lastKnown);
    } catch (_) {
      return null;
    }
  }

  /// Continuous updates, emitted every 10 meters of movement.
  Stream<LocationFix> watchFixes() {
    return Geolocator.getPositionStream(
      locationSettings: _streamSettings,
    ).map(_fixFrom);
  }

  double metersBetween(LatLng from, LatLng to) {
    return _distance.as(LengthUnit.Meter, from, to);
  }

  /// False on web, where `openAppSettings` throws instead of no-opping.
  bool get canOpenDeviceSettings => !kIsWeb;

  Future<bool> openDeviceSettings() async {
    if (!canOpenDeviceSettings) return false;
    return Geolocator.openAppSettings();
  }

  LocationFix _fixFrom(Position position) {
    return LocationFix(
      point: LatLng(position.latitude, position.longitude),
      accuracy: position.accuracy,
      timestamp: position.timestamp,
    );
  }
}
