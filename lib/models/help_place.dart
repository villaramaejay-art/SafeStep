import 'package:latlong2/latlong.dart';

/// The kinds of help SafeStep puts on the map.
enum HelpPlaceKind {
  police('police', 'Police station'),
  fireStation('fire_station', 'Fire station');

  const HelpPlaceKind(this.tag, this.label);

  /// The OpenStreetMap `amenity` value this kind is queried by.
  final String tag;

  final String label;

  static HelpPlaceKind? fromTag(String? value) {
    for (final kind in HelpPlaceKind.values) {
      if (kind.tag == value) return kind;
    }
    return null;
  }
}

/// A police or fire station near the user, from OpenStreetMap.
class HelpPlace {
  const HelpPlace({
    required this.id,
    required this.kind,
    required this.point,
    this.name,
  });

  final String id;
  final HelpPlaceKind kind;
  final LatLng point;

  /// Community data: plenty of stations are mapped without a name.
  final String? name;

  /// What to show on a pin or in an alert. Falls back to the kind so a nameless
  /// station is still identifiable as a station.
  String get label => name?.trim().isNotEmpty == true ? name!.trim() : kind.label;
}
