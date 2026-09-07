import 'package:flutter/material.dart';
import 'contacts_screen.dart';
import 'geofence_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'timer_screen.dart';

/// Holds the four sections behind one persistent bottom bar.
///
/// The sections are tabs rather than pushed routes, so there is nothing to pop
/// and no back button anywhere: every destination is always one tap away.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// A tab is built the first time it is opened and then kept alive by the
  /// IndexedStack, so switching back is instant and nothing refetches.
  final Set<int> _visited = {0};

  late final List<Widget> _views = [
    HomeScreen(onNavigate: _select),
    const ContactsScreen(),
    const GeofenceScreen(),
    const TimerScreen(),
    const HistoryScreen(),
  ];

  void _select(int index) {
    if (index == _index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _views.length; i++)
            if (_visited.contains(i)) _views[i] else const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts_rounded),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on_rounded),
            label: 'Safe Spaces',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer_rounded),
            label: 'Timer',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
