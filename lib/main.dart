import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/contacts_screen.dart';
import 'screens/geofence_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/timer_screen.dart';
import 'utils/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const SafeStepApp());
}

class SafeStepApp extends StatelessWidget {
  const SafeStepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeStep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/contacts': (context) => const ContactsScreen(),
        '/geofence': (context) => const GeofenceScreen(),
        '/timer': (context) => const TimerScreen(),
      },
    );
  }
}
