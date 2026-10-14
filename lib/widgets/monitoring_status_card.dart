import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../services/device_status_service.dart';
import '../services/timer_session_repository.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';

/// Shows what is actually armed right now, not what the user hopes is armed.
///
/// Each row states the one specific thing it checked - the timer's own
/// status, whether the background service is really running, the location
/// permission grant, the battery-optimization exemption - rather than
/// folding all of it into a single reassuring badge. A label like "Fully
/// Protected" would be a lie the moment any one of these is missing, and the
/// user has no way to tell which one from a badge like that.
class MonitoringStatusCard extends StatefulWidget {
  const MonitoringStatusCard({super.key});

  @override
  State<MonitoringStatusCard> createState() => _MonitoringStatusCardState();
}

class _MonitoringStatusCardState extends State<MonitoringStatusCard>
    with WidgetsBindingObserver {
  final DeviceStatusService _deviceStatusService = DeviceStatusService();
  final TimerSessionRepository _timerSessions = TimerSessionRepository();

  DeviceMonitoringStatus? _deviceStatus;
  TimerSession? _timerSession;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();

    // HomeScreen is kept alive in AppShell's IndexedStack once visited, so
    // navigating back to this tab does not rebuild it or re-run initState -
    // without its own polling, this card would show whatever was true the
    // one time it first mounted, long after a timer the user started (or
    // one restored by the plugin's own reboot/auto-restart path) actually
    // changed the real answer.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a Settings screen (permission or battery exemption)
    // should show the new state right away, not whatever was true before
    // the user left to go change it.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final status = await _deviceStatusService.current();
    final session = await _timerSessions.load();
    if (!mounted) return;
    setState(() {
      _deviceStatus = status;
      _timerSession = session;
    });
  }

  (String, Color) get _timerRow {
    switch (_timerSession?.status) {
      case TimerSessionStatus.running:
        return ('Active', AppColors.success);
      case TimerSessionStatus.paused:
        return ('Paused', AppColors.warning);
      case TimerSessionStatus.awaitingCheckIn:
        return ('Awaiting check-in', AppColors.danger);
      case TimerSessionStatus.expired:
        return ('Alert sent', AppColors.danger);
      case TimerSessionStatus.inactive:
      case null:
        return ('Inactive', AppColors.textTertiary);
    }
  }

  (String, Color) get _serviceRow {
    final running = _deviceStatus?.isServiceRunning ?? false;
    if (running) return ('Running', AppColors.success);

    final timerActive =
        _timerSession != null && _timerSession!.status != TimerSessionStatus.inactive;
    // The timer thinks it's doing something but nothing is actually running
    // it - the one combination that genuinely needs the user's attention,
    // not just a neutral "off" reading.
    return timerActive
        ? ('Not running - reopen the app', AppColors.danger)
        : ('Not running', AppColors.textTertiary);
  }

  (String, Color) get _locationRow {
    switch (_deviceStatus?.locationPermission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return ('Granted', AppColors.success);
      case LocationPermission.denied:
      case LocationPermission.deniedForever:
        return ('Denied', AppColors.danger);
      case LocationPermission.unableToDetermine:
      case null:
        return ('Unknown', AppColors.textTertiary);
    }
  }

  (String, Color) get _batteryRow {
    final ignoring = _deviceStatus?.isIgnoringBatteryOptimizations;
    if (ignoring == null) return ('Unknown', AppColors.textTertiary);
    return ignoring
        ? ('Unrestricted', AppColors.success)
        : ('Restricted - may stop monitoring', AppColors.warning);
  }

  bool get _canOpenBatterySettings =>
      _deviceStatus?.isIgnoringBatteryOptimizations == false;

  Widget _buildRow(String label, (String, Color) value, {VoidCallback? onTap}) {
    final (text, color) = value;

    final content = Row(
      children: [
        Expanded(child: Text(label, style: AppStyles.captionStyle)),
        AppSpacing.hGapSm,
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 4,
          ),
          decoration: AppStyles.pillDecoration(color),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      borderRadius: AppSpacing.small,
      onTap: onTap,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('SAFETY MONITORING', style: AppStyles.overlineStyle),
              ),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _load,
                  tooltip: 'Refresh status',
                ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          _buildRow('Safety timer', _timerRow),
          AppSpacing.gapSm,
          _buildRow('Background monitoring', _serviceRow),
          AppSpacing.gapSm,
          _buildRow('Location permission', _locationRow),
          AppSpacing.gapSm,
          _buildRow(
            'Battery optimization',
            _batteryRow,
            onTap: _canOpenBatterySettings
                ? () => FlutterForegroundTask.requestIgnoreBatteryOptimization()
                : null,
          ),
        ],
      ),
    );
  }
}
