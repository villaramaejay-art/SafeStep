import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/geocoding_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class SafeSpace {
  const SafeSpace({
    required this.name,
    required this.point,
    required this.radius,
    this.isCustom = false,
  });

  final String name;
  final LatLng point;
  final double radius;
  final bool isCustom;

  SafeSpace copyWith({
    String? name,
    LatLng? point,
    double? radius,
    bool? isCustom,
  }) {
    return SafeSpace(
      name: name ?? this.name,
      point: point ?? this.point,
      radius: radius ?? this.radius,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  static int _savedSelectedIndex = 0;
  static final List<SafeSpace> _savedSafeSpaces = [
    const SafeSpace(
      name: 'Home',
      point: LatLng(14.5995, 120.9842),
      radius: 3,
    ),
    const SafeSpace(
      name: 'Work',
      point: LatLng(14.5547, 121.0244),
      radius: 2,
    ),
    const SafeSpace(
      name: 'Gym',
      point: LatLng(14.6091, 121.0223),
      radius: 1.5,
    ),
  ];

  int get _selectedIndex => _savedSelectedIndex;
  List<SafeSpace> get _safeSpaces => _savedSafeSpaces;
  SafeSpace get _selectedSpace => _safeSpaces[_selectedIndex];
  final GeocodingService _geocodingService = GeocodingService();
  late double _draftRadius;

  @override
  void initState() {
    super.initState();
    _draftRadius = _selectedSpace.radius;
  }

  void _selectSafeSpace(int index) {
    setState(() {
      _savedSelectedIndex = index;
      _draftRadius = _selectedSpace.radius;
    });
  }

  void _saveSelectedRadius() {
    setState(() {
      _safeSpaces[_selectedIndex] = _selectedSpace.copyWith(
        radius: _draftRadius,
      );
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_selectedSpace.name} safe space saved.'),
      ),
    );
  }

  Future<void> _showAddSafeSpaceDialog() async {
    final nameController = TextEditingController();
    final searchController = TextEditingController();
    double newRadius = 2;
    bool isSearching = false;
    bool dialogIsOpen = true;
    String? searchError;
    LocationSearchResult? selectedResult;
    List<LocationSearchResult> results = [];

    final newSpace = await showDialog<SafeSpace>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> searchPlaces() async {
              final query = searchController.text.trim();

              if (query.isEmpty) {
                setDialogState(() {
                  searchError = 'Enter a place to search.';
                  results = [];
                });
                return;
              }

              setDialogState(() {
                isSearching = true;
                searchError = null;
                selectedResult = null;
                results = [];
              });

              try {
                final foundPlaces =
                    await _geocodingService.searchLocations(query);

                if (!dialogIsOpen) return;

                setDialogState(() {
                  results = foundPlaces;
                  searchError = foundPlaces.isEmpty
                      ? 'No matching locations found.'
                      : null;
                });
              } catch (_) {
                if (!dialogIsOpen) return;

                setDialogState(() {
                  searchError = 'Could not search locations right now.';
                  results = [];
                });
              } finally {
                if (dialogIsOpen) {
                  setDialogState(() => isSearching = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('Add safe location'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Safe space name',
                        hintText: 'Home, School, Clinic',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => searchPlaces(),
                            decoration: const InputDecoration(
                              labelText: 'Search exact location',
                              hintText: 'Type a place name or address',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 56,
                          child: FilledButton(
                            onPressed: isSearching ? null : searchPlaces,
                            child: isSearching
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.search_rounded),
                          ),
                        ),
                      ],
                    ),
                    if (searchError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        searchError!,
                        style: const TextStyle(
                          color: AppColors.panicPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (results.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: results.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final result = results[index];
                            final isSelected = selectedResult == result;

                            return InkWell(
                              onTap: () {
                                setDialogState(() {
                                  selectedResult = result;
                                  if (nameController.text.trim().isEmpty) {
                                    nameController.text = result.name;
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.panicPrimary.withValues(
                                          alpha: 0.12,
                                        )
                                      : AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.panicPrimary
                                        : AppColors.border,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? Icons.check_circle_rounded
                                          : Icons.place_outlined,
                                      color: AppColors.panicPrimary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            result.name,
                                            style: const TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            result.address,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppStyles.captionStyle,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      '${newRadius.toStringAsFixed(1)} km radius',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Slider(
                      value: newRadius,
                      min: 0.5,
                      max: 10,
                      divisions: 19,
                      label: newRadius.toStringAsFixed(1),
                      onChanged: (value) {
                        setDialogState(() => newRadius = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final nameExists = _safeSpaces.any((space) {
                      return space.name.toLowerCase() == name.toLowerCase();
                    });

                    if (name.isEmpty || selectedResult == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Add a name and select a location.'),
                        ),
                      );
                      return;
                    }

                    if (nameExists) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Use a unique safe location name.'),
                        ),
                      );
                      return;
                    }

                    Navigator.of(context).pop(
                      SafeSpace(
                        name: name,
                        point: selectedResult!.point,
                        radius: newRadius,
                        isCustom: true,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    dialogIsOpen = false;
    nameController.dispose();
    searchController.dispose();

    if (newSpace == null) return;

    setState(() {
      _safeSpaces.add(newSpace);
      _savedSelectedIndex = _safeSpaces.length - 1;
      _draftRadius = newSpace.radius;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${newSpace.name} location saved.'),
      ),
    );
  }

  Widget _buildSafeSpaceChip(int index) {
    final space = _safeSpaces[index];
    final isSelected = _selectedIndex == index;

    return ChoiceChip(
      avatar: space.isCustom
          ? Icon(
              Icons.add_location_alt_rounded,
              color: isSelected ? Colors.white : AppColors.panicPrimary,
              size: 18,
            )
          : null,
      label: Text(space.name),
      selected: isSelected,
      onSelected: (_) {
        _selectSafeSpace(index);
      },
      selectedColor: AppColors.panicPrimary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedSpace = _selectedSpace;
    final hasUnsavedRadius = _draftRadius != selectedSpace.radius;

    return Scaffold(
      appBar: AppBar(title: const Text('Safe Spaces & Geofencing')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose a safety zone',
                      style: AppStyles.sectionTitleStyle.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _showAddSafeSpaceDialog,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < _safeSpaces.length; i++)
                    _buildSafeSpaceChip(i),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
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
                              Text(
                                selectedSpace.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Saved safety perimeter',
                                style: AppStyles.captionStyle,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_draftRadius.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: AppColors.panicPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 300,
                        child: FlutterMap(
                          key: ValueKey(
                            '${selectedSpace.name}-${selectedSpace.point}',
                          ),
                          options: MapOptions(
                            initialCenter: selectedSpace.point,
                            initialZoom: 13,
                            minZoom: 3,
                            maxZoom: 18,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.drag |
                                  InteractiveFlag.pinchZoom |
                                  InteractiveFlag.doubleTapZoom |
                                  InteractiveFlag.scrollWheelZoom,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.safe_step',
                            ),
                            CircleLayer(
                              circles: [
                                CircleMarker(
                                  point: selectedSpace.point,
                                  radius: _draftRadius * 1000,
                                  useRadiusInMeter: true,
                                  color: AppColors.panicPrimary.withValues(
                                    alpha: 0.18,
                                  ),
                                  borderColor:
                                      AppColors.panicPrimary.withValues(
                                    alpha: 0.7,
                                  ),
                                  borderStrokeWidth: 2,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: selectedSpace.point,
                                  width: 56,
                                  height: 56,
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: AppColors.panicPrimary,
                                    size: 44,
                                  ),
                                ),
                              ],
                            ),
                            RichAttributionWidget(
                              attributions: [
                                TextSourceAttribution(
                                  'OpenStreetMap contributors',
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Adjust ${selectedSpace.name} radius',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This value is saved only for the selected safe space.',
                      style: AppStyles.captionStyle,
                    ),
                    Slider(
                      value: _draftRadius,
                      min: 0.5,
                      max: 10,
                      divisions: 19,
                      label: _draftRadius.toStringAsFixed(1),
                      onChanged: (value) {
                        setState(() => _draftRadius = value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            hasUnsavedRadius
                                ? 'Tap Save to confirm this radius.'
                                : 'Radius is saved for this safe space.',
                            style: AppStyles.captionStyle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed:
                              hasUnsavedRadius ? _saveSelectedRadius : null,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Save'),
                        ),
                      ],
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
}
