import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class SafetyWeather {
  const SafetyWeather({
    required this.temperature,
    required this.precipitation,
    required this.condition,
    required this.observedAt,
  });

  final double temperature;
  final double precipitation;
  final String condition;
  final DateTime observedAt;
}

class WeatherService {
  /// Used when the device location is unavailable.
  static const LatLng manilaFallback = LatLng(14.5995, 120.9842);

  /// Fetches conditions for [at], or for [manilaFallback] when [at] is null.
  Future<SafetyWeather> fetchCurrentConditions({LatLng? at}) async {
    final point = at ?? manilaFallback;

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': point.latitude.toString(),
      'longitude': point.longitude.toString(),
      'current': 'temperature_2m,precipitation,weather_code',
      'timezone': 'auto',
    });

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Weather request failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>;
    final weatherCode = (current['weather_code'] as num).toInt();

    return SafetyWeather(
      temperature: (current['temperature_2m'] as num).toDouble(),
      precipitation: (current['precipitation'] as num).toDouble(),
      condition: _conditionForCode(weatherCode),
      observedAt: DateTime.parse(current['time'] as String),
    );
  }

  String _conditionForCode(int code) {
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 67) return 'Rain nearby';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 99) return 'Storm risk';
    return 'Updated';
  }
}
