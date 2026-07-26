import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/app_styles.dart';
import '../widgets/panic_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  Widget _buildQuickTile(IconData icon, String title, String detail) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppStyles.cardDecoration.copyWith(
          color: AppColors.surfaceVariant,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.panicPrimary, size: 24),
            const SizedBox(height: 10),
            Text(title, style: AppStyles.sectionTitleStyle.copyWith(fontSize: 15)),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeStep'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: AppStyles.cardDecoration.copyWith(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF7FF), Color(0xFFFFFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.shield_outlined, color: AppColors.panicPrimary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your safety plan is active', style: AppStyles.sectionTitleStyle),
                          SizedBox(height: 4),
                          Text(
                            'Emergency contacts are ready and your safe zone is set.',
                            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _buildQuickTile(Icons.contacts_rounded, 'Contacts', 'Trusted people ready'),
                  const SizedBox(width: 12),
                  _buildQuickTile(Icons.location_on_rounded, 'Safe Spaces', 'Pinned zones'),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _buildQuickTile(Icons.timer_rounded, 'Timer', 'Check-in reminders'),
                  const SizedBox(width: 12),
                  _buildQuickTile(Icons.help_center_rounded, 'Support', 'Quick guidance'),
                ],
              ),
              const Spacer(),
              PanicButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Panic alert triggered (placeholder).')),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'One-touch activation for urgent assistance',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 1) {
            Navigator.pushNamed(context, '/contacts');
          } else if (index == 2) {
            Navigator.pushNamed(context, '/geofence');
          } else if (index == 3) {
            Navigator.pushNamed(context, '/timer');
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.contacts_rounded), label: 'Contacts'),
          NavigationDestination(icon: Icon(Icons.location_on_rounded), label: 'Safe Spaces'),
          NavigationDestination(icon: Icon(Icons.timer_rounded), label: 'Timer'),
        ],
      ),
    );
  }
}
