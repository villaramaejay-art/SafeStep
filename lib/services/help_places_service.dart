import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/help_place.dart';

/// Finds police and fire stations around a point, from OpenStreetMap.
///
/// Uses Overpass rather than Nominatim: Nominatim is a geocoder built to answer
/// "where is this name", while Overpass answers "what is tagged like this near
/// here", which is the question being asked.
///
/// The data is contributed by mappers, so coverage varies and a fair number of
/// stations carry no name. Neither is treated as an error - a pin with no label
/// is still a station worth knowing about.
class HelpPlacesService {
  HelpPlacesService({http.Client? client}) : _client = client;

  static const String _host = 'overpass-api.de';
  static const String _path = '/api/interpreter';

  /// Overpass is a free, shared service. Results are held so panning the map or
  /// revisiting the tab does not re-ask for something that has not changed.
  static const Duration cacheLife = Duration(minutes: 30);

  /// Coordinates are rounded to this many decimals for the cache key: about
  /// 1 km, well inside the search radius, so small movements reuse the answer.
  static const int _keyDecimals = 2;

  final http.Client? _client;

  static final Map<String, _CachedPlaces> _cache = {};

  static void clearCache() => _cache.clear();

  /// Stations within [radiusMeters] of [around], nearest first.
  ///
  /// Never throws: a failed lookup returns an empty list, because this is a
  /// convenience layer on a map and must not take the screen down with it.
  Future<List<HelpPlace>> findNearby(
    LatLng around, {
    int radiusMeters = 10000,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final key = '${around.latitude.toStringAsFixed(_keyDecimals)},'
        '${around.longitude.toStringAsFixed(_keyDecimals)},$radiusMeters';

    final cached = _cache[key];
    if (cached != null && !cached.isStale) return cached.places;

    try {
      final query = _buildQuery(around, radiusMeters);
      final uri = Uri.https(_host, _path);

      final response = await (_client?.post ?? http.post)(
        uri,
        headers: const {
          'User-Agent': 'safe_step_flutter_app',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'data': query},
      ).timeout(timeout);

      if (response.statusCode != 200) return const [];

      final places = _parse(response.body);
      _sortByDistanceFrom(around, places);

      _cache[key] = _CachedPlaces(places, DateTime.now());
      return places;
    } catch (_) {
      // Offline, rate limited, or malformed - the map simply shows no pins.
      return const [];
    }
  }

  /// Both node and way are asked for: a small station is mapped as a single
  /// point, a large one as a building outline. `out center` collapses the
  /// outline to a point so both come back the same shape.
  static String _buildQuery(LatLng around, int radiusMeters) {
    final lat = around.latitude;
    final lon = around.longitude;
    final tags = HelpPlaceKind.values.map((k) => k.tag).join('|');
    final filter = '["amenity"~"$tags"](around:$radiusMeters,$lat,$lon);';

    return '[out:json][timeout:25];(node$filter way$filter);out center tags;';
  }

  static List<HelpPlace> _parse(String body) {
    final data = jsonDecode(body) as Map<String, dynamic>;
    final elements = data['elements'] as List<dynamic>? ?? const [];
    final places = <HelpPlace>[];

    for (final element in elements) {
      if (element is! Map<String, dynamic>) continue;

      final tags = element['tags'] as Map<String, dynamic>?;
      final kind = HelpPlaceKind.fromTag(tags?['amenity'] as String?);
      if (kind == null) continue;

      // A way carries its position under `center`, a node directly.
      final center = element['center'] as Map<String, dynamic>?;
      final lat = (element['lat'] ?? center?['lat']) as num?;
      final lon = (element['lon'] ?? center?['lon']) as num?;
      if (lat == null || lon == null) continue;

      places.add(
        HelpPlace(
          id: '${element['type']}/${element['id']}',
          kind: kind,
          point: LatLng(lat.toDouble(), lon.toDouble()),
          name: tags?['name'] as String?,
        ),
      );
    }

    return places;
  }

  static void _sortByDistanceFrom(LatLng origin, List<HelpPlace> places) {
    const distance = Distance();
    places.sort((a, b) {
      return distance
          .as(LengthUnit.Meter, origin, a.point)
          .compareTo(distance.as(LengthUnit.Meter, origin, b.point));
    });
  }
}

class _CachedPlaces {
  const _CachedPlaces(this.places, this.fetchedAt);

  final List<HelpPlace> places;
  final DateTime fetchedAt;

  bool get isStale =>
      DateTime.now().difference(fetchedAt) > HelpPlacesService.cacheLife;
}
