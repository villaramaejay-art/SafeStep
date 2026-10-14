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
        // Both read the same persisted TimerSession on the way back up
        // (see SafetyTaskHandler.onStart), so a timer that was running when
        // the phone rebooted or the app was updated mid-countdown picks up
        // exactly where it left off instead of silently going dark.
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        // The plugin's own restart alarm (ForegroundService.onDestroy /
        // onTaskRemoved, via RestartReceiver) is what stands in for a
        // hand-rolled AlarmManager backup here: if an OEM task-killer or the
        // OS takes the service out while a timer is still active, it is
        // scheduled to relaunch within 1-5 seconds, landing back in the same
        // onStart recovery path. allowAutoRestart defaults to true; set here
        // explicitly so that guarantee is visible at the call site rather
        // than resting on an unstated default.
        allowAutoRestart: true,
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
