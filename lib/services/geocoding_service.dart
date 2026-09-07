import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class LocationSearchResult {
  const LocationSearchResult({
    required this.name,
    required this.address,
    required this.point,
  });

  final String name;
  final String address;
  final LatLng point;
}

class GeocodingService {
  Future<List<LocationSearchResult>> searchLocations(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'addressdetails': '1',
      'limit': '5',
    });

    final response = await http.get(
      uri,
      headers: const {
        'User-Agent': 'safe_step_flutter_app',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Location search failed: ${response.statusCode}');
    }

    final results = jsonDecode(response.body) as List<dynamic>;

    return results.map((item) {
      final data = item as Map<String, dynamic>;
      final displayName = data['display_name'] as String? ?? 'Unknown place';
      final latitude = double.parse(data['lat'] as String);
      final longitude = double.parse(data['lon'] as String);
      final shortName = displayName.split(',').first.trim();

      return LocationSearchResult(
        name: shortName.isEmpty ? displayName : shortName,
        address: displayName,
        point: LatLng(latitude, longitude),
      );
    }).toList();
  }

  /// Turns a position into somewhere a person can drive to.
  ///
  /// Carriers here strip SMS containing map links, so the alert cannot rely on
  /// a tappable URL. A street and a barangay is what actually gets somebody to
  /// the door - coordinates still ride along underneath for exactness.
  ///
  /// Returns null rather than throwing: this runs inside an emergency, and an
  /// alert must never wait on, or fail because of, a nicety.
  Future<String?> describePlace(
    LatLng point, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'json',
        'addressdetails': '1',
        // Roughly street level. Finer than this returns building numbers that
        // are usually missing here; coarser returns just the city.
        'zoom': '17',
      });

      final response = await http
          .get(uri, headers: const {'User-Agent': 'safe_step_flutter_app'})
          .timeout(timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;
      if (address == null) return null;

      return _shortPlaceName(address);
    } catch (_) {
      return null;
    }
  }

  /// The two or three parts of an address that actually help someone find you,
  /// nearest first. Nominatim's own `display_name` runs to a region, a postcode
  /// and a country, none of which fit in an SMS or tell a local anything.
  static String? _shortPlaceName(Map<String, dynamic> address) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = address[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
      return null;
    }

    final street = pick(['road', 'pedestrian', 'footway', 'residential']);
    final area = pick(['neighbourhood', 'suburb', 'village', 'hamlet', 'quarter']);
    final town = pick(['city', 'town', 'municipality', 'county']);

    final parts = [street, area, town].whereType<String>().toList();
    if (parts.isEmpty) return null;

    final label = parts.join(', ');

    // An SMS has no room for a runaway address, and the leading parts are the
    // specific ones.
    return label.length <= 60 ? label : '${label.substring(0, 57)}...';
  }
}
