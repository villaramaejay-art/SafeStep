import 'package:latlong2/latlong.dart';

/// A geofenced area the user considers safe.
class SafeSpace {
  /// The range a safe space may cover, in kilometres.
  ///
  /// Kept deliberately tight. A perimeter measured in kilometres covers a whole
  /// town, so leaving it says almost nothing about whether the user is in
  /// trouble - and an alert that vague is one their contacts learn to ignore.
  /// At this size, crossing the boundary means they have actually left.
  static const double minRadiusKm = 0.1;
  static const double maxRadiusKm = 0.5;
  static const double defaultRadiusKm = 0.3;

  /// The slider moves in 50 m steps across the range.
  static const int radiusDivisions = 8;

  /// Radii are small enough now that kilometres read badly: "0.3 km" is worse
  /// than "300 m" for a distance somebody is about to walk.
  static String formatRadius(double km) => '${(km * 1000).round()} m';

  /// Brings a stored radius into the range the app can now show.
  ///
  /// Rows saved before the limits tightened can hold several kilometres, and a
  /// Slider throws when handed a value outside its own bounds.
  static double clampRadius(double km) =>
      km.clamp(minRadiusKm, maxRadiusKm).toDouble();

  const SafeSpace({
    required this.id,
    required this.name,
    required this.point,
    required this.radius,
    this.isCustom = true,
  });

  factory SafeSpace.fromMap(Map<String, dynamic> map) {
    return SafeSpace(
      id: map['id'] as String,
      name: map['name'] as String,
      point: LatLng(
        (map['latitude'] as num).toDouble(),
        (map['longitude'] as num).toDouble(),
      ),
      radius: (map['radius_km'] as num).toDouble(),
      isCustom: map['is_custom'] as bool? ?? true,
    );
  }

  final String id;
  final String name;
  final LatLng point;

  /// Geofence radius in kilometres.
  final double radius;

  /// Always true now that accounts start empty - every safe space is one the
  /// user chose. Kept because rows written before the defaults were removed
  /// carry it, and the column still records where a space came from.
  final bool isCustom;

  Map<String, dynamic> toInsert() {
    return {
      'name': name,
      'latitude': point.latitude,
      'longitude': point.longitude,
      'radius_km': radius,
      'is_custom': isCustom,
    };
  }

  SafeSpace copyWith({
    String? name,
    LatLng? point,
    double? radius,
    bool? isCustom,
  }) {
    return SafeSpace(
      id: id,
      name: name ?? this.name,
      point: point ?? this.point,
      radius: radius ?? this.radius,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}
