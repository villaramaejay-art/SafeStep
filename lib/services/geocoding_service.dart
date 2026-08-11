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
}
