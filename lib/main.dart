import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'utils/app_colors.dart';
import 'utils/app_styles.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  if (!SupabaseConfig.isConfigured) {
    runApp(const _StartupErrorApp(message: SupabaseConfig.missingMessage));
    return;
  }

  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.key,
    );
  } catch (error) {
    runApp(
      _StartupErrorApp(message: 'Could not reach Supabase.\n\n$error'),
    );
    return;
  }

  runApp(const SafeStepApp());
}

class SafeStepApp extends StatelessWidget {
  const SafeStepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeStep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AuthGate(),
    );
  }
}

/// Shows the dashboard when a Supabase session exists, the login screen
/// otherwise. Sign-in and sign-out therefore need no manual navigation.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return auth.currentSession == null
            ? const LoginScreen()
            : const AppShell();
      },
    );
  }
}

/// Standalone app shown when the build has no usable Supabase credentials.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeStep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: AppStyles.cardDecoration,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10),
                        Text('SafeStep cannot start', style: AppStyles.titleStyle),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SelectableText(
                      message,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.5,
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
