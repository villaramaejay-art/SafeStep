import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import 'background/foreground_service_controller.dart';

/// What is actually true about the device right now, for the monitoring
/// status card - not what the app hopes is true.
///
/// Every field here is read fresh from the OS at the moment it's asked for,
/// not cached or assumed from whatever permission dialog the user last saw.
class DeviceMonitoringStatus {
  const DeviceMonitoringStatus({
    required this.isServiceRunning,
    required this.locationPermission,
    required this.isIgnoringBatteryOptimizations,
  });

  final bool isServiceRunning;
  final LocationPermission locationPermission;

  /// True = the OS will not throttle this app for battery saving, which is
  /// what actually keeps a backgrounded foreground service alive under
  /// Doze/App Standby. Null only off Android, where the question does not
  /// apply.
  final bool? isIgnoringBatteryOptimizations;
}

class DeviceStatusService {
  Future<DeviceMonitoringStatus> current() async {
    final isRunning = await ForegroundServiceController.isRunning;
    final permission = await Geolocator.checkPermission();

    bool? ignoringOptimizations;
    if (ForegroundServiceController.isSupported) {
      try {
        ignoringOptimizations =
            await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      } catch (_) {
        ignoringOptimizations = null;
      }
    }

    return DeviceMonitoringStatus(
      isServiceRunning: isRunning,
      locationPermission: permission,
      isIgnoringBatteryOptimizations: ignoringOptimizations,
    );
  }
}
