import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'safety_task_handler.dart';

/// Starts, stops, and configures the Android foreground service that keeps
/// the Safety Timer running while the app is backgrounded or the screen is
/// locked.
///
/// Android only, same reasoning as [EmergencyService.isSupported]: no other
/// platform this app ships on needs or supports a persistent background
/// service for this.
class ForegroundServiceController {
  static const int serviceId = 4821;

  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Call once at app start, before anything else here. Safe to call more
  /// than once.
  static void initCommunicationPort() {
    if (!isSupported) return;
    FlutterForegroundTask.initCommunicationPort();
  }

  /// Registers the notification channel and service behaviour. Must run
  /// before [start]. Does not request any permission itself.
  static void configure() {
    if (!isSupported) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'safestep_monitoring',
        channelName: 'Safety monitoring',
        channelDescription:
            'Shown while SafeStep is watching your safety timer in the '
            'background.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Notification permission (Android 13+) and the battery-optimization
  /// exemption prompt. Both are best-effort: the service still runs if the
  /// user declines, just less reliably - callers should reflect that in the
  /// UI rather than block on it.
  static Future<void> requestPermissions() async {
    if (!isSupported) return;

    final notificationPermission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (notificationPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  static Future<bool> get isRunning async {
    if (!isSupported) return false;
    return FlutterForegroundTask.isRunningService;
  }

  static Future<ServiceRequestResult> start({
    required String title,
    required String text,
  }) async {
    if (await isRunning) {
      return FlutterForegroundTask.restartService();
    }

    return FlutterForegroundTask.startService(
      serviceId: serviceId,
      notificationTitle: title,
      notificationText: text,
      callback: safetyTaskHandlerStartCallback,
    );
  }

  static Future<ServiceRequestResult> stop() {
    return FlutterForegroundTask.stopService();
  }
}
