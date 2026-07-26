import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  String selectedLocation = 'Home';
  double radius = 6.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Safe Spaces & Geofencing')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a safety zone', style: AppStyles.sectionTitleStyle.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: ['Home', 'Work', 'Gym'].map((location) {
                  final isSelected = selectedLocation == location;
                  return ChoiceChip(
                    label: Text(location),
                    selected: isSelected,
                    onSelected: (_) => setState(() => selectedLocation = location),
                    selectedColor: AppColors.panicPrimary,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : AppColors.textPrimary),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Safety perimeter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 180,
                            decoration: BoxDecoration(
                              color: AppColors.panicPrimary.withValues(alpha: 0.12),
                              border: Border.all(color: AppColors.panicPrimary.withValues(alpha: 0.45)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            height: 120,
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.18),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.65)),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const Icon(Icons.location_on_rounded, color: AppColors.panicPrimary, size: 42),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('${radius.toStringAsFixed(1)} km radius', style: const TextStyle(color: AppColors.textSecondary)),
                    Slider(
                      value: radius,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: radius.toStringAsFixed(1),
                      onChanged: (value) => setState(() => radius = value),
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
