import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:latlong2/latlong.dart';

import '../models/help_place.dart';

/// One station the user has just come within range of.
class NearbyHelp {
  const NearbyHelp({required this.place, required this.meters});

  final HelpPlace place;
  final double meters;
}

/// Decides which stations the user has just entered the range of.
///
/// Deliberately a pure class with no notification or location dependency, so
/// the rule that governs when the user is interrupted can be tested directly.
///
/// The rule: alert once on the way in, and stay quiet until the user has left
/// again. Somebody standing near a station - or living down the road from one -
/// is not told about it over and over. That matters more than it sounds: an app
/// that interrupts you when nothing is wrong teaches you to ignore it, and the
/// same notification channel carries the alerts that do matter.
class ProximityWatcher {
  ProximityWatcher({
    this.radiusMeters = defaultRadiusMeters,
    Distance? distance,
  }) : _distance = distance ?? const Distance();

  /// Deliberately tight: about a minute on foot.
  ///
  /// A wider ring would fire on the way past rather than on arrival, and in a
  /// town where the police station sits a few hundred metres from home that is
  /// a notification most days. At this distance the station is in sight.
  static const double defaultRadiusMeters = 100;

  /// The band beyond the radius that must be cleared before a station can
  /// announce itself again, so a user sitting on the boundary - or a GPS fix
  /// wobbling across it - is not alerted repeatedly. Comfortably wider than a
  /// typical phone's accuracy.
  static const double exitMarginMeters = 60;

  final double radiusMeters;
  final Distance _distance;

  final Set<String> _inside = {};

  /// Forgets which stations are currently in range, so the next reading is
  /// treated as fresh. Used when tracking stops or the place list changes.
  void reset() => _inside.clear();

  /// The stations newly entered at [position]. Empty on every reading that
  /// crosses nothing.
  List<NearbyHelp> evaluate(LatLng position, List<HelpPlace> places) {
    final entered = <NearbyHelp>[];

    for (final place in places) {
      final meters = _distance.as(LengthUnit.Meter, position, place.point);
      final wasInside = _inside.contains(place.id);

      if (meters <= radiusMeters) {
        if (!wasInside) {
          _inside.add(place.id);
          entered.add(NearbyHelp(place: place, meters: meters));
        }
      } else if (meters > radiusMeters + exitMarginMeters) {
        _inside.remove(place.id);
      }
      // Between the two: keep the previous verdict rather than flapping.
    }

    return entered;
  }
}

/// Shows the proximity notifications.
///
/// Separate from [ProximityWatcher] so the decision and the interruption can be
/// changed independently - and so the decision stays testable without a device.
class ProximityNotifier {
  ProximityNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const String _channelId = 'safestep_nearby_help';
  static const String _channelName = 'Nearby help';
  static const String _channelDescription =
      'Tells you when a police or fire station is close by.';

  final FlutterLocalNotificationsPlugin _plugin;

  bool _ready = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Prepares the plugin and asks for permission. Safe to call repeatedly.
  ///
  /// Returns false when notifications cannot be shown, so the caller can fall
  /// back rather than believe an alert was delivered.
  Future<bool> prepare() async {
    if (!isSupported) return false;
    if (_ready) return true;

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // Android 13+ requires the runtime grant; older versions return null and
      // are already allowed.
      final granted = await android?.requestNotificationsPermission();
      _ready = granted ?? true;

      return _ready;
    } catch (_) {
      return false;
    }
  }

  Future<void> show(NearbyHelp help) async {
    if (!await prepare()) return;

    final distance = help.meters < 1000
        ? '${help.meters.round()} m away'
        : '${(help.meters / 1000).toStringAsFixed(1)} km away';

    try {
      await _plugin.show(
        // Stable per station, so re-entering replaces the old notification
        // rather than stacking a second copy of the same fact.
        id: help.place.id.hashCode & 0x7fffffff,
        title: help.place.kind == HelpPlaceKind.police
            ? 'Police station nearby'
            : 'Fire station nearby',
        body: '${help.place.label} - $distance',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            // Deliberately quiet: this is background awareness, not an alarm.
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
    } catch (_) {
      // A notification that cannot be shown is not worth failing anything over.
    }
  }
}
