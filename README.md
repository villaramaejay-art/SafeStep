# SafeStep

SafeStep is a Flutter safety companion app prototype. It includes emergency contacts, a panic action, safe-space geofencing, a safety timer, weather-based local safety conditions, and API-powered location search.

## Features

- Email/password accounts backed by Supabase Auth
- Emergency contacts and safe spaces saved to your account, per user
- Accounts start with no safe spaces: every zone is one the user chose
- Emergency contacts screen
- Safety timer with start, pause, resume, reset, and completion alert
- The safety timer stops itself once you reach a safe space, so arriving is the check-in
- Interactive geofencing map using OpenStreetMap tiles
- Live GPS tracking with an accuracy circle and inside/outside safe-zone status
- Tap-to-pin mode for creating a safe space anywhere on the map
- Dashed distance line from your position to the selected safe space
- Map controls for centering on yourself or on the selected zone
- Per-location saved safe-space radius
- Rename or remove a safe space, with confirmation before removal
- Add custom safe locations by searching exact places or addresses
- Automated emergency SMS on Android: panic button, missed timer check-in, and leaving a safe space
- An "I'm safe now" follow-up SMS that stands the alert down
- Alert history: every SMS sent, with the time, the location and who it reached
- Weather card on the Home screen based on your live GPS position

## API Integrations

This project demonstrates public API usage with HTTP GET requests, JSON processing, and UI display.

- **Open-Meteo Forecast API**
  - Used for current local safety weather conditions.
  - Displays condition, temperature, and rain amount on the Home screen.

- **OpenStreetMap Nominatim Search API**
  - Used for searching exact locations when adding a custom safe space.
  - Displays search results in the Geofencing screen.

See [API_DOCUMENTATION.md](API_DOCUMENTATION.md) for endpoint details, sample JSON, and integration explanation.

## Main Dependencies

- `supabase_flutter` - auth and Postgres database
- `flutter_map` - Leaflet-style map rendering for Flutter
- `latlong2` - coordinates and distance math
- `geolocator` - device GPS position and permissions
- `another_telephony` - sends the emergency SMS on Android
- `http`
- `cupertino_icons`

## Emergency SMS

Three things send an SMS to every saved contact, with the sender's name and
their position. They do **not** all say the same thing:

| Trigger | Reads as | Grace period |
| --- | --- | --- |
| Panic button pressed | `SafeStep ALERT` - needs help | 5 seconds to cancel |
| Safety timer ends with no check-in | `SafeStep ALERT` - needs help | 10 seconds to check in |
| Leaving the selected safe space | `SafeStep UPDATE` - left the zone | none - sends on the crossing |

Leaving a zone is a notice, not an alarm. It says where somebody is, not that
anything has happened to them, and it never asks for help - a contact told
"needs help" every time the user walks to the shop stops reading the message
that means it. Only the two real emergencies open the all-clear loop.

The message is sent from the handset by `another_telephony`, so it uses the
user's own SIM and load.

**Android only.** No other mobile platform lets an app send an SMS without the
user pressing send. On web and iOS the app reports that instead of failing
silently.

**Distribute as an APK.** Google Play restricts the `SEND_SMS` permission, so
publishing would need a permissions declaration and review.

Guards against wasted messages:

- A 60-second cooldown per trigger, so a stuck trigger cannot spam contacts.
- Geofence exits use hysteresis: a reading only counts as outside once it
  clears the radius by more than its own GPS accuracy, so noise at the boundary
  does not fire an alert.
- Every alert is written to the `alerts` table with recipient and delivery
  counts.

### Standing the alert down

An alert opens a loop: the contacts know something is wrong and have no way to
learn that it is over. While an emergency is the most recent thing sent, and for
12 hours after it, the Home screen offers **I'm safe now** - a follow-up SMS on
the same channel that raised the alarm, logged as an `all_clear`.

It asks for confirmation first. An accidental all-clear tells people to stop
worrying, which is the one mistake here that makes things worse rather than
merely noisier.

### Alert history

The History tab lists every SMS the app has sent for the account: what it was,
when, how many contacts it reached, and whether a location went with it. Tapping
an entry shows the exact message body the contacts received, with buttons to
copy it or the map link.

The SMS itself leaves from the handset and is never seen again, so this table is
the only record that it happened.

#### Navigation

The five sections are tabs inside `AppShell`, not pushed routes, so the bottom
bar is on every screen and there is no back button. A tab is built on first
visit and then kept alive, so switching away and back does not refetch or lose
state - live GPS tracking keeps running, for example.

## Known limits

The timer and the geofence watcher only run while the app is in the foreground.
If the app is closed or the OS suspends it, neither will fire. Making them
survive that needs a server-side deadline for the timer and a background
location service for the geofence.

## Permissions

Live location requires platform permissions, already declared in:

- `android/app/src/main/AndroidManifest.xml` - `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `SEND_SMS`
- `ios/Runner/Info.plist` - `NSLocationWhenInUseUsageDescription`

On web, the browser prompts for location and requires `https` or `localhost`.

## Getting Started

Install dependencies:

```bash
flutter pub get
```

SafeStep needs a Supabase project. Follow [SUPABASE_SETUP.md](SUPABASE_SETUP.md)
once.

Whenever `supabase/schema.sql` changes, paste it into the Supabase SQL Editor
and run it again. It is idempotent, so re-running is always safe, and the app
will tell you which table is missing if you forget.

Then run with your credentials:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Analyze the project:

```bash
flutter analyze
```

Run tests:

```bash
flutter test
```

## Project Structure

```text
lib/
  models/
  screens/
  services/
  utils/
  widgets/
```

Important files:

- `lib/screens/app_shell.dart` - the four tabs behind one persistent bottom bar
- `lib/screens/home_screen.dart` - dashboard, setup summary and panic button
- `lib/screens/geofence_screen.dart` - map, live location, safe spaces, location search
- `lib/screens/timer_screen.dart` - safety timer
- `lib/screens/history_screen.dart` - alert history and the message that was sent
- `lib/services/weather_service.dart` - Open-Meteo API integration
- `lib/services/geocoding_service.dart` - Nominatim API integration
- `lib/services/location_service.dart` - GPS permissions, fixes, and distance math
- `lib/services/auth_service.dart` - Supabase email/password auth
- `lib/services/contacts_repository.dart` - contacts CRUD
- `lib/services/safe_spaces_repository.dart` - safe spaces CRUD (add, rename, radius, remove)
- `lib/services/emergency_service.dart` - composes and sends the emergency SMS and the all-clear
- `lib/services/alerts_repository.dart` - reads the alert log
- `lib/models/alert_record.dart` - alert reasons, one logged alert, and the stand-down rule
- `supabase/schema.sql` - tables, RLS policies, and triggers

## Notes

The weather card uses the device's GPS position when permission is granted, and falls back to Manila coordinates otherwise.

Emergency contacts and safe spaces live in Supabase and are scoped to the signed-in user by row level security. See [SUPABASE_SETUP.md](SUPABASE_SETUP.md).
