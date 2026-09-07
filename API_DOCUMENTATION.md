# API Documentation

## API Name

SafeStep uses two public APIs:

1. **Open-Meteo Forecast API**  
   Used to get current local weather conditions for the Home screen.

2. **OpenStreetMap Nominatim Search API**  
   Used to search exact place names or addresses when adding a custom safe location in the Geofencing screen.

## API Endpoint(s) Used

### 1. Open-Meteo Forecast API

**Endpoint:**

```text
https://api.open-meteo.com/v1/forecast
```

**HTTP Method:** `GET`

**Query Parameters Used:**

```text
latitude={device_latitude}
longitude={device_longitude}
current=temperature_2m,precipitation,weather_code
timezone=auto
```

**Purpose:**  
This endpoint retrieves the current temperature, rainfall amount, and weather condition code for the selected coordinates.

The latitude and longitude come from the device's GPS position through `LocationService`. When location permission is denied or unavailable, the app falls back to Manila (`14.5995`, `120.9842`). `timezone=auto` lets the API resolve the time zone from the coordinates instead of assuming `Asia/Manila`.

### 2. OpenStreetMap Nominatim Search API

**Endpoint:**

```text
https://nominatim.openstreetmap.org/search
```

**HTTP Method:** `GET`

**Query Parameters Used:**

```text
q={user_search_text}
format=json
addressdetails=1
limit=5
```

**Purpose:**  
This endpoint searches for locations based on the user's typed place name or address. The app uses the returned latitude and longitude to create a custom safe space.

## Sample JSON Response

### Open-Meteo Sample Response

```json
{
  "latitude": 14.625,
  "longitude": 121.0,
  "timezone": "Asia/Manila",
  "current": {
    "time": "2026-08-11T19:30",
    "interval": 900,
    "temperature_2m": 28.6,
    "precipitation": 0.0,
    "weather_code": 2
  }
}
```

### Nominatim Sample Response

```json
[
  {
    "place_id": 123456789,
    "licence": "Data (c) OpenStreetMap contributors",
    "lat": "14.5995124",
    "lon": "120.9842195",
    "display_name": "Manila, Capital District, Metro Manila, Philippines",
    "type": "city",
    "importance": 0.78
  }
]
```

## Explanation of Integration

The project integrates public APIs using the `http` package in Flutter. Both integrations use an HTTP `GET` request, decode the JSON response, process the needed fields, and display the processed data in the user interface.

### Weather Integration

The weather integration is implemented in:

```text
lib/services/weather_service.dart
```

The app sends a `GET` request to the Open-Meteo Forecast API. After receiving the response, the app uses `jsonDecode(response.body)` to convert the JSON into Dart data. It reads the `current` object and extracts:

- `temperature_2m`
- `precipitation`
- `weather_code`
- `time`

The numeric `weather_code` is converted into a readable condition such as `Clear`, `Cloudy`, `Rain nearby`, or `Storm risk`. The processed weather data is displayed on the Home screen in the **Local safety conditions** card.

### Location Search Integration

The location search integration is implemented in:

```text
lib/services/geocoding_service.dart
```

When a user taps **Add** in the Geofencing screen, they can search for an exact location by typing a place name or address. The app sends that text to the Nominatim Search API using a `GET` request.

The JSON response is decoded and processed into location search results. For each result, the app extracts:

- `display_name`
- `lat`
- `lon`

The location results are displayed in the Add Safe Location dialog. When the user selects a result and saves it, the app stores the safe space name, map coordinates, and selected radius. The chosen location then appears in the Geofencing UI with a map marker and radius circle.
