import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/help_place.dart';
import '../models/safe_space.dart';
import '../services/contacts_repository.dart' show RepositoryFailure;
import '../services/emergency_service.dart';
import '../services/geocoding_service.dart';
import '../services/help_places_service.dart';
import '../services/location_service.dart';
import '../services/proximity_alerts.dart';
import '../services/safe_spaces_repository.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../utils/text_format.dart';
import '../widgets/info_banner.dart';
import '../widgets/status_view.dart';

/// Validates a proposed safe-space name, returning null when it is usable.
typedef NameValidator = String? Function(String name);

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final GeocodingService _geocodingService = GeocodingService();
  final HelpPlacesService _helpPlacesService = HelpPlacesService();
  final LocationService _locationService = LocationService();
  final SafeSpacesRepository _repository = SafeSpacesRepository();
  final EmergencyService _emergencyService = EmergencyService();
  final MapController _mapController = MapController();

  /// Null until the first fix; used to spot the inside -> outside transition.
  bool? _wasInside;

  List<SafeSpace> _safeSpaces = [];
  int _selectedIndex = 0;
  double _draftRadius = SafeSpace.defaultRadiusKm;
  bool _isLoading = true;
  String? _loadError;

  /// Police and fire stations around the user, and whether they are shown.
  ///
  /// Off by default: this is a map of where help is, not something the app
  /// should start interrupting people about uninvited.
  List<HelpPlace> _helpPlaces = [];
  bool _showHelpPlaces = false;
  bool _isLoadingHelpPlaces = false;
  LatLng? _helpPlacesCenter;

  final ProximityWatcher _proximityWatcher = ProximityWatcher();
  final ProximityNotifier _proximityNotifier = ProximityNotifier();

  bool _mapIsReady = false;
  bool _pinModeEnabled = false;
  bool _isLocating = false;
  bool _showRoute = true;
  LocationFix? _userFix;
  String? _locationError;
  LocationFailure? _locationFailure;
  StreamSubscription<LocationFix>? _locationSubscription;

  bool get _isTrackingLive => _locationSubscription != null;

  SafeSpace? get _selectedSpace =>
      _safeSpaces.isEmpty ? null : _safeSpaces[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // --- Data -----------------------------------------------------------------

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final spaces = await _repository.fetchAll();
      if (!mounted) return;

      setState(() {
        _safeSpaces = spaces;
        _selectedIndex =
            spaces.isEmpty ? 0 : _selectedIndex.clamp(0, spaces.length - 1);
        _draftRadius = spaces.isEmpty
            ? SafeSpace.defaultRadiusKm
            : SafeSpace.clampRadius(spaces[_selectedIndex].radius);
        _isLoading = false;
      });
    } on RepositoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadError = failure.message;
        _isLoading = false;
      });
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --- Map camera -----------------------------------------------------------

  void _moveCamera(LatLng point, {double? zoom}) {
    if (!_mapIsReady) return;
    _mapController.move(point, zoom ?? _mapController.camera.zoom);
  }

  /// Zoom level that keeps a circle of [radiusKm] roughly in frame.
  double _zoomForRadius(double radiusKm) {
    // Tuned for the 100-500 m range a safe space now covers: at the old
    // town-scale zooms the circle was a dot.
    if (radiusKm <= 0.15) return 17;
    if (radiusKm <= 0.3) return 16;
    return 15;
  }

  // --- Live location --------------------------------------------------------

  Future<void> _startLiveLocation() async {
    setState(() {
      _isLocating = true;
      _locationError = null;
      _locationFailure = null;
    });

    try {
      final fix = await _locationService.getCurrentFix();

      if (!mounted) return;

      _locationSubscription = _locationService.watchFixes().listen(
        (update) {
          if (!mounted) return;
          setState(() => _userFix = update);
          _evaluateGeofence(update);
          _evaluateProximity(update);
        },
        onError: (_) {
          if (!mounted) return;
          _locationSubscription?.cancel();
          setState(() {
            _locationSubscription = null;
            _locationError = 'Live tracking stopped unexpectedly.';
          });
        },
      );

      setState(() {
        _userFix = fix;
        _isLocating = false;
      });

      // Seeds _wasInside so the first reading cannot itself look like an exit.
      _evaluateGeofence(fix);
      _evaluateProximity(fix);
      _moveCamera(fix.point, zoom: 15);
    } on LocationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _locationError = error.message;
        _locationFailure = error.failure;
      });
    }
  }

  void _stopLiveLocation() {
    _locationSubscription?.cancel();
    setState(() {
      _locationSubscription = null;
      _userFix = null;
      _wasInside = null;
    });
    // Nothing is being watched any more, so the next session starts fresh.
    _proximityWatcher.reset();
  }

  /// Fires one alert on the inside -> outside transition.
  ///
  /// Uses hysteresis rather than a single threshold: a reading only counts as
  /// outside once it clears the radius by more than its own accuracy, so GPS
  /// noise at the boundary cannot flap and send repeated messages. The saved
  /// radius is used, not the unsaved slider value.
  Future<void> _evaluateGeofence(LocationFix fix) async {
    final space = _selectedSpace;
    if (space == null) return;

    final meters = _locationService.metersBetween(fix.point, space.point);
    final radiusMeters = space.radius * 1000;

    final bool nowInside;
    if (meters <= radiusMeters) {
      nowInside = true;
    } else if (meters > radiusMeters + fix.accuracy) {
      nowInside = false;
    } else {
      return; // Inside the uncertainty band - keep the previous verdict.
    }

    final wasInside = _wasInside;
    _wasInside = nowInside;

    final hasLeft = wasInside == true && !nowInside;
    if (!hasLeft) return;

    if (EmergencyService.isCoolingDown(AlertReason.leftSafeSpace)) return;

    final outcome = await _emergencyService.sendAlert(
      reason: AlertReason.leftSafeSpace,
      safeSpaceName: space.name,
      knownLocation: fix,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Left ${space.name}. ${outcome.summary}'),
        backgroundColor:
            outcome.isSuccess ? AppColors.success : AppColors.danger,
      ),
    );
  }

  // --- Nearby help ----------------------------------------------------------

  /// Blue for police, red for fire - the colours those services already use, so
  /// the two are told apart without reading a label.
  static Color _helpColor(HelpPlaceKind kind) {
    return kind == HelpPlaceKind.police ? AppColors.primary : AppColors.danger;
  }

  static IconData _helpIcon(HelpPlaceKind kind) {
    return kind == HelpPlaceKind.police
        ? Icons.local_police_rounded
        : Icons.local_fire_department_rounded;
  }

  /// Loads the stations around [around], unless the ones already held cover it.
  ///
  /// Overpass is a shared free service, so this deliberately does not refetch
  /// on every position update - only when the user has moved far enough that
  /// the previous answer no longer describes where they are.
  Future<void> _loadHelpPlaces(LatLng around, {bool force = false}) async {
    final lastCenter = _helpPlacesCenter;

    if (!force && lastCenter != null) {
      final moved = _locationService.metersBetween(lastCenter, around);
      if (moved < 3000) return;
    }

    setState(() => _isLoadingHelpPlaces = true);

    final places = await _helpPlacesService.findNearby(around);
    if (!mounted) return;

    setState(() {
      _helpPlaces = places;
      _helpPlacesCenter = around;
      _isLoadingHelpPlaces = false;
    });

    // A different set of stations means the previous in-range verdicts describe
    // places that may no longer be in the list.
    _proximityWatcher.reset();
  }

  Future<void> _toggleHelpPlaces() async {
    if (_showHelpPlaces) {
      setState(() => _showHelpPlaces = false);
      _proximityWatcher.reset();
      return;
    }

    setState(() => _showHelpPlaces = true);

    final around = _userFix?.point ?? _selectedSpace?.point;
    if (around == null) return;

    await _loadHelpPlaces(around, force: _helpPlaces.isEmpty);
    if (!mounted) return;

    // Asked for at the moment the user opts in, rather than on first launch
    // where it would have no context.
    await _proximityNotifier.prepare();

    if (!mounted) return;
    if (_helpPlaces.isEmpty) {
      _notify('No police or fire stations are mapped near here.');
    } else {
      _notify('${TextFormat.count(_helpPlaces.length, 'station')} nearby.');
    }
  }

  /// Notifies once for each station the user has just come within range of.
  Future<void> _evaluateProximity(LocationFix fix) async {
    if (!_showHelpPlaces || _helpPlaces.isEmpty) return;

    final entered = _proximityWatcher.evaluate(fix.point, _helpPlaces);

    for (final help in entered) {
      await _proximityNotifier.show(help);

      if (!mounted) return;
      // Shown in the app as well: the alert is quiet by design, and the user is
      // most likely looking at this screen while tracking.
      _notify('${help.place.label} is ${help.meters.round()} m away.');
    }
  }

  void _centerOnUser() {
    final fix = _userFix;

    if (fix == null) {
      _startLiveLocation();
      return;
    }

    _moveCamera(fix.point, zoom: 15);
  }

  // --- Safe space management ------------------------------------------------

  void _selectSafeSpace(int index) {
    setState(() {
      _selectedIndex = index;
      _draftRadius = SafeSpace.clampRadius(_safeSpaces[index].radius);
      // A different zone means the previous inside/outside verdict is moot.
      _wasInside = null;
    });

    _moveCamera(
      _safeSpaces[index].point,
      zoom: _zoomForRadius(_safeSpaces[index].radius),
    );
  }

  Future<void> _saveSelectedRadius() async {
    final space = _selectedSpace;
    if (space == null) return;

    try {
      await _repository.updateRadius(space.id, _draftRadius);
      if (!mounted) return;

      setState(() {
        _safeSpaces[_selectedIndex] = space.copyWith(radius: _draftRadius);
      });
      _notify('${space.name} safe space saved.');
    } on RepositoryFailure catch (failure) {
      _notify(failure.message);
    }
  }

  /// Returns a user-facing error, or null when [name] is usable.
  ///
  /// [excludingId] is the space being renamed - without it, keeping a name the
  /// same would collide with itself.
  String? _safeSpaceNameError(String name, {String? excludingId}) {
    if (name.isEmpty) return 'Add a name for this safe space.';

    final nameExists = _safeSpaces.any((space) {
      if (space.id == excludingId) return false;
      return space.name.toLowerCase() == name.toLowerCase();
    });

    return nameExists ? 'Use a unique safe location name.' : null;
  }

  Future<void> _renameSelected() async {
    final space = _selectedSpace;
    if (space == null) return;

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameSafeSpaceDialog(
        currentName: space.name,
        validate: (value) =>
            _safeSpaceNameError(value, excludingId: space.id),
      ),
    );

    if (newName == null || !mounted || newName == space.name) return;

    try {
      await _repository.rename(space.id, newName);
      if (!mounted) return;

      setState(() {
        _safeSpaces[_selectedIndex] = space.copyWith(name: newName);
      });
      _notify('Renamed to $newName.');
    } on RepositoryFailure catch (failure) {
      _notify(failure.message);
    }
  }

  Future<void> _confirmRemoveSelected() async {
    final space = _selectedSpace;
    if (space == null) return;

    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove safe space?'),
        content: Text(
          '${space.name} will no longer be watched, and leaving it will not '
          'alert your contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (shouldRemove != true || !mounted) return;

    try {
      await _repository.delete(space.id);
      if (!mounted) return;

      setState(() {
        _safeSpaces.removeAt(_selectedIndex);

        // The selection has to land somewhere real: the list may now be
        // shorter, or empty.
        _selectedIndex =
            _safeSpaces.isEmpty ? 0 : _selectedIndex.clamp(0, _safeSpaces.length - 1);
        _draftRadius = _safeSpaces.isEmpty
            ? SafeSpace.defaultRadiusKm
            : SafeSpace.clampRadius(_safeSpaces[_selectedIndex].radius);

        // The watcher was judging the deleted zone. Cleared so the first
        // reading against the new one cannot look like an exit.
        _wasInside = null;
      });

      _notify('${space.name} removed.');

      final next = _selectedSpace;
      if (next != null) {
        _moveCamera(next.point, zoom: _zoomForRadius(next.radius));
      }
    } on RepositoryFailure catch (failure) {
      _notify(failure.message);
    }
  }

  Future<void> _addSafeSpace(SafeSpace draft) async {
    try {
      final saved = await _repository.add(draft);
      if (!mounted) return;

      setState(() {
        _safeSpaces.add(saved);
        _selectedIndex = _safeSpaces.length - 1;
        _draftRadius = SafeSpace.clampRadius(saved.radius);
        _pinModeEnabled = false;
      });

      _moveCamera(saved.point, zoom: _zoomForRadius(saved.radius));
      _notify('${saved.name} location saved.');
    } on RepositoryFailure catch (failure) {
      _notify(failure.message);
    }
  }

  // --- Dialogs --------------------------------------------------------------

  void _handleMapTap(TapPosition _, LatLng point) {
    if (!_pinModeEnabled) return;
    _showPinDialog(point);
  }

  Future<void> _showPinDialog(LatLng point) async {
    final draft = await showDialog<SafeSpace>(
      context: context,
      builder: (_) => _PinSafeSpaceDialog(
        point: point,
        validateName: _safeSpaceNameError,
      ),
    );

    if (draft == null || !mounted) return;
    await _addSafeSpace(draft);
  }

  Future<void> _showAddSafeSpaceDialog() async {
    final draft = await showDialog<SafeSpace>(
      context: context,
      builder: (_) => _AddSafeSpaceDialog(
        geocodingService: _geocodingService,
        validateName: _safeSpaceNameError,
      ),
    );

    if (draft == null || !mounted) return;
    await _addSafeSpace(draft);
  }

  // --- Formatting -----------------------------------------------------------

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildSafeSpaceChip(int index) {
    final space = _safeSpaces[index];
    final isSelected = _selectedIndex == index;

    return ChoiceChip(
      avatar: Icon(
        // Every safe space is one the user pinned, so they all wear the pin.
        Icons.push_pin_rounded,
        size: 15,
        color: isSelected ? Colors.white : AppColors.primary,
      ),
      label: Text(space.name),
      selected: isSelected,
      onSelected: (_) => _selectSafeSpace(index),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildLiveLocationCard(SafeSpace selectedSpace) {
    final fix = _userFix;
    final error = _locationError;

    late final IconData icon;
    late final Color accent;
    late final String title;
    late final String detail;

    if (_isLocating) {
      icon = Icons.my_location_rounded;
      accent = AppColors.primary;
      title = 'Finding your location';
      detail = 'Waiting for a GPS fix...';
    } else if (error != null) {
      icon = Icons.location_disabled_rounded;
      accent = AppColors.danger;
      title = 'Live location unavailable';
      detail = error;
    } else if (fix != null) {
      final meters = _locationService.metersBetween(
        fix.point,
        selectedSpace.point,
      );
      final isInside = meters <= _draftRadius * 1000;

      icon = isInside ? Icons.verified_user_rounded : Icons.run_circle_outlined;
      accent = isInside ? AppColors.success : AppColors.warning;
      title = isInside
          ? 'Inside ${selectedSpace.name}'
          : 'Outside ${selectedSpace.name}';
      detail = '${_formatDistance(meters)} from the center '
          '(+/- ${fix.accuracy.round()} m accuracy)';
    } else {
      icon = Icons.location_searching_rounded;
      accent = AppColors.textTertiary;
      title = 'Live location is off';
      detail = 'Turn it on to see where you are against your safe zones.';
    }

    final showSettingsButton =
        _locationFailure == LocationFailure.permissionDeniedForever &&
            _locationService.canOpenDeviceSettings;

    // Sits directly under the map, so it reads as a caption on what is drawn
    // there rather than as a competing card. Recessed and single-row: the map
    // is the feature, and this took a third of the screen when it was stacked
    // above with a full-width button.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppStyles.sunkenDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: AppStyles.iconTileDecoration(color: accent),
                child: _isLocating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(icon, color: accent, size: 18),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppStyles.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppStyles.captionStyle.copyWith(fontSize: 11.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AppSpacing.hGapSm,
              _isTrackingLive
                  ? OutlinedButton(
                      onPressed: _stopLiveLocation,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                      ),
                      child: const Text('Stop'),
                    )
                  : FilledButton.icon(
                      onPressed: _isLocating ? null : _startLiveLocation,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                      ),
                      icon: const Icon(Icons.my_location_rounded, size: 16),
                      label: Text(error != null ? 'Retry' : 'Track'),
                    ),
            ],
          ),
          // Only when the user has permanently refused location, where the way
          // out is a trip to Settings and deserves its own full-width target.
          if (showSettingsButton) ...[
            AppSpacing.gapSm,
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _locationService.openDeviceSettings,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Leaflet-style control stack pinned to the top-right of the map.
  Widget _buildMapControls(SafeSpace selectedSpace) {
    Widget control({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
      bool isActive = false,
    }) {
      return Tooltip(
        message: tooltip,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppSpacing.small,
            boxShadow: [
              BoxShadow(
                color: AppColors.textPrimary.withValues(alpha: 0.14),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: isActive ? AppColors.primary : AppColors.surface,
            borderRadius: AppSpacing.small,
            child: InkWell(
              borderRadius: AppSpacing.small,
              onTap: onPressed,
              child: SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  icon,
                  size: 19,
                  color: isActive ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        control(
          icon: Icons.my_location_rounded,
          tooltip: 'Center on my location',
          onPressed: _centerOnUser,
          isActive: _userFix != null,
        ),
        control(
          icon: Icons.place_rounded,
          tooltip: 'Center on ${selectedSpace.name}',
          onPressed: () => _moveCamera(
            selectedSpace.point,
            zoom: _zoomForRadius(_draftRadius),
          ),
        ),
        control(
          icon: Icons.add_location_alt_rounded,
          tooltip: _pinModeEnabled ? 'Cancel pin mode' : 'Tap map to pin',
          isActive: _pinModeEnabled,
          onPressed: () =>
              setState(() => _pinModeEnabled = !_pinModeEnabled),
        ),
        control(
          icon: _showRoute ? Icons.timeline_rounded : Icons.timeline_outlined,
          tooltip: _showRoute ? 'Hide distance line' : 'Show distance line',
          isActive: _showRoute,
          onPressed: () => setState(() => _showRoute = !_showRoute),
        ),
        control(
          icon: _isLoadingHelpPlaces
              ? Icons.hourglass_top_rounded
              : Icons.local_police_rounded,
          tooltip: _showHelpPlaces
              ? 'Hide police and fire stations'
              : 'Show police and fire stations',
          isActive: _showHelpPlaces,
          onPressed: () {
            if (!_isLoadingHelpPlaces) _toggleHelpPlaces();
          },
        ),
      ],
    );
  }

  Widget _buildMap(SafeSpace selectedSpace) {
    final fix = _userFix;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: selectedSpace.point,
        initialZoom: _zoomForRadius(selectedSpace.radius),
        minZoom: 3,
        maxZoom: 18,
        onTap: _handleMapTap,
        onMapReady: () => _mapIsReady = true,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.safe_step',
        ),
        CircleLayer(
          circles: [
            CircleMarker(
              point: selectedSpace.point,
              radius: _draftRadius * 1000,
              useRadiusInMeter: true,
              color: AppColors.primary.withValues(alpha: 0.16),
              borderColor: AppColors.primary.withValues(alpha: 0.75),
              borderStrokeWidth: 2,
            ),
            if (fix != null)
              CircleMarker(
                point: fix.point,
                radius: fix.accuracy,
                useRadiusInMeter: true,
                color: AppColors.success.withValues(alpha: 0.16),
                borderColor: AppColors.success.withValues(alpha: 0.5),
                borderStrokeWidth: 1,
              ),
            // The range each station announces itself from.
            if (_showHelpPlaces)
              for (final place in _helpPlaces)
                CircleMarker(
                  point: place.point,
                  radius: _proximityWatcher.radiusMeters,
                  useRadiusInMeter: true,
                  color: _helpColor(place.kind).withValues(alpha: 0.10),
                  borderColor: _helpColor(place.kind).withValues(alpha: 0.45),
                  borderStrokeWidth: 1,
                ),
          ],
        ),
        if (fix != null && _showRoute)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [fix.point, selectedSpace.point],
                strokeWidth: 3,
                color: AppColors.primary.withValues(alpha: 0.75),
                pattern: StrokePattern.dashed(segments: const [10, 8]),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (_showHelpPlaces)
              for (final place in _helpPlaces)
                Marker(
                  point: place.point,
                  width: 34,
                  height: 34,
                  child: Tooltip(
                    message: place.label,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _helpColor(place.kind),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _helpIcon(place.kind),
                        color: _helpColor(place.kind),
                        size: 18,
                      ),
                    ),
                  ),
                ),
            Marker(
              point: selectedSpace.point,
              width: 44,
              height: 44,
              child: const Icon(
                Icons.location_on_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            if (fix != null)
              Marker(
                point: fix.point,
                width: 24,
                height: 24,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              textStyle: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedSpaceCard(SafeSpace selectedSpace) {
    final hasUnsavedRadius = _draftRadius != selectedSpace.radius;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selectedSpace.name, style: AppStyles.sectionTitleStyle),
                    const SizedBox(height: 2),
                    Text(
                      'Saved safety perimeter',
                      style: AppStyles.captionStyle,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: AppStyles.pillDecoration(AppColors.primary),
                child: Text(
                  SafeSpace.formatRadius(_draftRadius),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Safe space options',
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      _renameSelected();
                    case 'remove':
                      _confirmRemoveSelected();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: AppSpacing.md),
                        Text('Rename'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: AppColors.danger,
                        ),
                        SizedBox(width: AppSpacing.md),
                        Text(
                          'Remove',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.gapLg,
          if (_pinModeEnabled)
            InfoBanner(
              message: 'Tap anywhere on the map to pin a new safe space.',
              icon: Icons.touch_app_rounded,
              color: AppColors.primary,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
            ),
          ClipRRect(
            borderRadius: AppSpacing.medium,
            child: SizedBox(
              // The map is what this screen is for - where the user is against
              // the zone they drew. Everything else is a control for it.
              height: 440,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildMap(selectedSpace)),
                  Positioned(
                    top: AppSpacing.sm,
                    right: AppSpacing.sm,
                    child: _buildMapControls(selectedSpace),
                  ),
                ],
              ),
            ),
          ),
          AppSpacing.gapMd,
          _buildLiveLocationCard(selectedSpace),
          AppSpacing.gapXl,
          Row(
            children: [
              Expanded(
                child: Text(
                  'ADJUST RADIUS',
                  style: AppStyles.overlineStyle,
                ),
              ),
              Text(
                hasUnsavedRadius ? 'Unsaved' : 'Saved',
                style: AppStyles.captionStyle.copyWith(
                  fontWeight: FontWeight.w700,
                  color: hasUnsavedRadius
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
            ],
          ),
          Slider(
            value: _draftRadius,
            min: SafeSpace.minRadiusKm,
            max: SafeSpace.maxRadiusKm,
            divisions: SafeSpace.radiusDivisions,
            label: SafeSpace.formatRadius(_draftRadius),
            onChanged: (value) => setState(() => _draftRadius = value),
          ),
          AppSpacing.gapSm,
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: hasUnsavedRadius ? _saveSelectedRadius : null,
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('Save radius'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SizedBox(
        height: 360,
        child: StatusView.loading(message: 'Loading your safe spaces...'),
      );
    }

    if (_loadError != null) {
      return SizedBox(
        height: 360,
        child: StatusView(
          icon: Icons.cloud_off_rounded,
          tone: AppColors.danger,
          title: 'Could not load your safe spaces',
          message: _loadError!,
          action: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ),
      );
    }

    final selectedSpace = _selectedSpace;

    if (selectedSpace == null) {
      return SizedBox(
        height: 360,
        child: StatusView(
          icon: Icons.location_off_rounded,
          title: 'No safe spaces yet',
          message: 'Search for a place and save it as a safe space to start '
              'tracking whether you are inside it.',
          action: FilledButton.icon(
            onPressed: _showAddSafeSpaceDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add a safe space'),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < _safeSpaces.length; i++) _buildSafeSpaceChip(i),
          ],
        ),
        AppSpacing.gapLg,
        _buildSelectedSpaceCard(selectedSpace),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Safe Spaces'),
        actions: [
          // Up here rather than a floating button: a FAB sits over the bottom
          // right of the map, which is the one thing on this screen worth
          // seeing, and it covered the tracking control underneath it.
          if (_safeSpaces.isNotEmpty)
            IconButton(
              onPressed: _isLoading ? null : _showAddSafeSpaceDialog,
              icon: const Icon(Icons.add_location_alt_rounded),
              tooltip: 'Add a safe space',
            ),
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh safe spaces',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxxl,
          ),
          child: _buildBody(),
        ),
      ),
    );
  }
}

/// Names a safe space at a point the user tapped on the map.
///
/// A widget rather than a closure so the controller lives exactly as long as
/// the dialog route does. Disposing it right after `showDialog` resolves
/// crashes the exit animation, which still rebuilds the fields.
class _PinSafeSpaceDialog extends StatefulWidget {
  const _PinSafeSpaceDialog({
    required this.point,
    required this.validateName,
  });

  final LatLng point;
  final NameValidator validateName;

  @override
  State<_PinSafeSpaceDialog> createState() => _PinSafeSpaceDialogState();
}

class _PinSafeSpaceDialogState extends State<_PinSafeSpaceDialog> {
  final TextEditingController _nameController = TextEditingController();
  double _radius = SafeSpace.defaultRadiusKm;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final error = widget.validateName(name);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    Navigator.of(context).pop(
      SafeSpace(
        id: '', // assigned by the database on insert
        name: name,
        point: widget.point,
        radius: _radius,
        isCustom: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pin a safe space'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppStyles.sunkenDecoration,
              child: Row(
                children: [
                  const Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      '${widget.point.latitude.toStringAsFixed(5)}, '
                      '${widget.point.longitude.toStringAsFixed(5)}',
                      style: AppStyles.captionStyle,
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.gapLg,
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Safe space name',
                hintText: 'Home, School, Clinic',
                prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
              ),
            ),
            AppSpacing.gapXl,
            Row(
              children: [
                const Expanded(
                  child: Text('RADIUS', style: AppStyles.overlineStyle),
                ),
                Text(
                  SafeSpace.formatRadius(_radius),
                  style: AppStyles.labelStyle.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            Slider(
              value: _radius,
              min: SafeSpace.minRadiusKm,
              max: SafeSpace.maxRadiusKm,
              divisions: SafeSpace.radiusDivisions,
              label: SafeSpace.formatRadius(_radius),
              onChanged: (value) => setState(() => _radius = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Finds a safe space by searching Nominatim for a place name or address.
class _AddSafeSpaceDialog extends StatefulWidget {
  const _AddSafeSpaceDialog({
    required this.geocodingService,
    required this.validateName,
  });

  final GeocodingService geocodingService;
  final NameValidator validateName;

  @override
  State<_AddSafeSpaceDialog> createState() => _AddSafeSpaceDialogState();
}

class _AddSafeSpaceDialogState extends State<_AddSafeSpaceDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  double _radius = SafeSpace.defaultRadiusKm;
  bool _isSearching = false;
  String? _searchError;
  LocationSearchResult? _selectedResult;
  List<LocationSearchResult> _results = [];

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchPlaces() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _searchError = 'Enter a place to search.';
        _results = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _selectedResult = null;
      _results = [];
    });

    try {
      final foundPlaces = await widget.geocodingService.searchLocations(query);

      if (!mounted) return;

      setState(() {
        _results = foundPlaces;
        _searchError =
            foundPlaces.isEmpty ? 'No matching locations found.' : null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _searchError = 'Could not search locations right now.';
        _results = [];
      });
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _submit() {
    final result = _selectedResult;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a location from the results.')),
      );
      return;
    }

    final name = _nameController.text.trim();
    final error = widget.validateName(name);

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }

    Navigator.of(context).pop(
      SafeSpace(
        id: '', // assigned by the database on insert
        name: name,
        point: result.point,
        radius: _radius,
        isCustom: true,
      ),
    );
  }

  Widget _buildResultTile(LocationSearchResult result) {
    final isSelected = _selectedResult == result;

    return Material(
      color: isSelected ? AppColors.surfaceVariant : AppColors.surface,
      borderRadius: AppSpacing.medium,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedResult = result;
            if (_nameController.text.trim().isEmpty) {
              _nameController.text = result.name;
            }
          });
        },
        borderRadius: AppSpacing.medium,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppSpacing.medium,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.place_outlined,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
                size: 20,
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.name,
                      style: AppStyles.labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      result.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppStyles.captionStyle.copyWith(fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add safe location'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Safe space name',
                  hintText: 'Home, School, Clinic',
                  prefixIcon: Icon(Icons.label_outline_rounded, size: 20),
                ),
              ),
              AppSpacing.gapLg,
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _searchPlaces(),
                      decoration: const InputDecoration(
                        labelText: 'Search exact location',
                        hintText: 'Place name or address',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  SizedBox(
                    height: 56,
                    width: 56,
                    child: FilledButton(
                      onPressed: _isSearching ? null : _searchPlaces,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                      ),
                      child: _isSearching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
              if (_searchError != null) ...[
                AppSpacing.gapMd,
                InfoBanner(
                  message: _searchError!,
                  icon: Icons.info_outline_rounded,
                  color: AppColors.warning,
                  margin: EdgeInsets.zero,
                ),
              ],
              if (_results.isNotEmpty) ...[
                AppSpacing.gapMd,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 210),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => AppSpacing.gapSm,
                    itemBuilder: (context, index) =>
                        _buildResultTile(_results[index]),
                  ),
                ),
              ],
              AppSpacing.gapXl,
              Row(
                children: [
                  const Expanded(
                    child: Text('RADIUS', style: AppStyles.overlineStyle),
                  ),
                  Text(
                    SafeSpace.formatRadius(_radius),
                    style: AppStyles.labelStyle.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _radius,
                min: SafeSpace.minRadiusKm,
                max: SafeSpace.maxRadiusKm,
                divisions: SafeSpace.radiusDivisions,
                label: SafeSpace.formatRadius(_radius),
                onChanged: (value) => setState(() => _radius = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Renames one safe space.
///
/// A StatefulWidget rather than a StatefulBuilder so the controller is disposed
/// with the dialog. Disposing it at the call site tears it down while the exit
/// animation is still rebuilding the field.
class _RenameSafeSpaceDialog extends StatefulWidget {
  const _RenameSafeSpaceDialog({
    required this.currentName,
    required this.validate,
  });

  final String currentName;

  /// Returns a message to show, or null when the name is usable.
  final String? Function(String) validate;

  @override
  State<_RenameSafeSpaceDialog> createState() => _RenameSafeSpaceDialogState();
}

class _RenameSafeSpaceDialogState extends State<_RenameSafeSpaceDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    final error = widget.validate(name);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename safe space'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        // Clears the moment the user starts fixing it, rather than sitting
        // there contradicting what is now on screen.
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          labelText: 'Safe space name',
          prefixIcon: const Icon(Icons.label_outline_rounded, size: 20),
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
