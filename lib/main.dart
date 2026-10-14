import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'services/alert_cooldown_store.dart';
import 'services/background/foreground_service_controller.dart';
import 'utils/app_colors.dart';
import 'utils/app_styles.dart';
import 'utils/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Must happen before any FlutterForegroundTask call, in every isolate that
  // makes one - this sets up the UI-isolate side of the port the background
  // task uses to talk back.
  ForegroundServiceController.initCommunicationPort();

  // Set once before the first frame, so the very first paint already matches
  // the device's current setting instead of flashing light and then
  // switching.
  AppColors.applyBrightness(
    WidgetsBinding.instance.platformDispatcher.platformBrightness,
  );

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

  // Before any screen can read EmergencyService.isCoolingDown (a synchronous
  // call, e.g. from the geofence exit check) - otherwise the very first
  // check in this isolate would read an empty cache instead of what was
  // actually persisted.
  await AlertCooldownStore.hydrate();

  runApp(const SafeStepApp());
}

/// Follows the system's light/dark setting for the life of the app.
///
/// [AppColors] holds the actual color values and is updated in place, so
/// screens keep reading `AppColors.primary` exactly as before. What this
/// widget adds is the trigger: when the OS reports a brightness change, it
/// updates the palette and rebuilds from the root, so every screen re-reads
/// the new colors without losing its own state - a tab's scroll position, a
/// running timer, a live GPS subscription, none of it resets just because the
/// sun went down.
class SafeStepApp extends StatefulWidget {
  const SafeStepApp({super.key});

  @override
  State<SafeStepApp> createState() => _SafeStepAppState();
}

class _SafeStepAppState extends State<SafeStepApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    final changed = AppColors.applyBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
    // Only rebuilds MaterialApp itself, for the ThemeData passed to `theme:`
    // (the app bar, the nav bar, dialogs, buttons - anything Theme.of(context)
    // drives). `home` stays the same const AuthGate instance throughout, on
    // purpose: AuthGate sits inside the Navigator's initial route, and a
    // route whose page widget changes identity gets rebuilt as a new route,
    // which would recreate AppShell's State along with it - the running
    // timer, the live GPS subscription, the selected tab, all reset for no
    // reason better than "the OS flipped a setting". AuthGate repaints its
    // own subtree through its own observer below instead.
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeStep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      // Material-driven chrome (app bars, buttons, dialogs, the nav bar) eases
      // between the two palettes instead of snapping the instant the OS
      // setting flips.
      themeAnimationDuration: const Duration(milliseconds: 320),
      themeAnimationCurve: Curves.easeOut,
      home: const AuthGate(),
    );
  }
}

/// Shows the dashboard when a Supabase session exists, the login screen
/// otherwise. Sign-in and sign-out therefore need no manual navigation.
///
/// Watches platform brightness itself, independently of [SafeStepApp], so it
/// can repaint its own subtree (AppShell's tabs, the login form) in place -
/// without ever changing its own widget identity and triggering a Navigator-
/// level rebuild of the route it lives in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  // Read once and reused for the life of this State: StreamBuilder treats a
  // new Stream instance as a brand new subscription and briefly reports
  // ConnectionState.waiting while it resubscribes, which - because that
  // branch below returns a different widget type - unmounts AppShell
  // entirely. Re-reading `auth.onAuthStateChange` fresh on every rebuild (as
  // this used to) fed StreamBuilder a new instance each time and tripped
  // exactly that, which is what was resetting the selected tab and any
  // running timer on every brightness change.
  late final Stream<AuthState> _authStateChanges =
      Supabase.instance.client.auth.onAuthStateChange;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // AppColors itself is already updated by SafeStepApp's own observer;
    // this setState just forces AppShell/LoginScreen to rebuild in place so
    // they re-read it, the same way any other state change here would.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: _authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Fresh instances, not const: AppShell/LoginScreen need to actually
        // rebuild when this widget's own setState above fires.
        return auth.currentSession == null ? LoginScreen() : AppShell();
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
      theme: AppTheme.build(),
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
                    Row(
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Text('SafeStep cannot start', style: AppStyles.titleStyle),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SelectableText(
                      message,
                      style: TextStyle(
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
