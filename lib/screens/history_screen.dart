import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alert_record.dart';
import '../services/alerts_repository.dart';
import '../services/contacts_repository.dart' show RepositoryFailure;
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../utils/text_format.dart';
import '../widgets/status_view.dart';

/// The record of every SMS the app has sent for this account.
///
/// An alert leaves the phone and is never seen again, so without this the user
/// has no way to check afterwards what went out, to how many people, or from
/// where.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.repository});

  /// Injected by tests. The app leaves it null and talks to Supabase.
  final AlertsRepository? repository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final AlertsRepository _repository =
      widget.repository ?? AlertsRepository();

  List<AlertRecord> _alerts = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final alerts = await _repository.fetchRecent();
      if (!mounted) return;
      setState(() {
        _alerts = alerts;
        _isLoading = false;
      });
    } on RepositoryFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadError = failure.message;
        _isLoading = false;
      });
    }
  }

  /// The accent for a row, so the list can be read at a glance: red is somebody
  /// asking for help, green is the all-clear, and blue is a location update
  /// that never claimed either.
  static Color _toneFor(AlertRecord alert) {
    if (alert.delivered == 0) return AppColors.warning;

    return switch (alert.reason.tone) {
      AlertTone.emergency => AppColors.danger,
      AlertTone.notice => AppColors.primary,
      AlertTone.standDown => AppColors.success,
    };
  }

  static IconData _iconFor(AlertRecord alert) {
    switch (alert.reason) {
      case AlertReason.panic:
        return Icons.emergency_share_rounded;
      case AlertReason.timerExpired:
        return Icons.timer_off_rounded;
      case AlertReason.leftSafeSpace:
        return Icons.wrong_location_rounded;
      case AlertReason.allClear:
        return Icons.verified_rounded;
    }
  }

  /// Shows the exact text the contacts received. The summary in the list is a
  /// paraphrase; this is the thing itself.
  Future<void> _showMessage(AlertRecord alert) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) => _MessageSheet(alert: alert),
    );
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildSummary() {
    final emergencies = _alerts.where((a) => a.reason.isEmergency).length;

    final String detail;
    if (emergencies == 0) {
      detail = 'No emergency alerts have been sent from this account.';
    } else {
      detail = '${TextFormat.count(emergencies, 'alert')} sent. Tap any entry '
          'to read the exact message your contacts received.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.tintedDecoration,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppSpacing.medium,
            ),
            child: Icon(
              emergencies == 0
                  ? Icons.shield_outlined
                  : Icons.receipt_long_rounded,
              color: emergencies == 0 ? AppColors.success : AppColors.primary,
              size: 20,
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(child: Text(detail, style: AppStyles.captionStyle)),
        ],
      ),
    );
  }

  Widget _buildAlertCard(AlertRecord alert) {
    final tone = _toneFor(alert);

    return Material(
      color: AppColors.surface,
      borderRadius: AppSpacing.large,
      child: InkWell(
        borderRadius: AppSpacing.large,
        onTap: () => _showMessage(alert),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: AppStyles.cardDecoration,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: AppStyles.iconTileDecoration(color: tone),
                child: Icon(_iconFor(alert), color: tone, size: 22),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.title,
                            style: AppStyles.sectionTitleStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        AppSpacing.hGapSm,
                        Text(
                          formatRelativeTime(alert.createdAt),
                          style: AppStyles.captionStyle.copyWith(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _Chip(
                          icon: alert.delivered == 0
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          label: alert.deliverySummary,
                          color: alert.delivered == 0
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                        _Chip(
                          icon: alert.hasLocation
                              ? Icons.place_rounded
                              : Icons.location_disabled_rounded,
                          label: alert.hasLocation
                              ? 'Location shared'
                              : 'No location',
                          color: alert.hasLocation
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                      ],
                    ),
                    // The exact timestamp used to sit here as well, saying the
                    // same thing as "2 hr ago" twice on every row. It lives in
                    // the message sheet, where somebody checking a record
                    // actually needs it.
                    // "Not delivered" on its own sends the user hunting for a
                    // bug in the app. The network's own reason usually names
                    // something they can fix.
                    if (alert.failure != null) ...[
                      AppSpacing.gapSm,
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration:
                            AppStyles.statusDecoration(AppColors.warning),
                        child: Text(
                          alert.failure!,
                          style: AppStyles.captionStyle.copyWith(
                            fontSize: 11.5,
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const StatusView.loading(message: 'Loading your alert history...');
    }

    final error = _loadError;
    if (error != null) {
      return StatusView(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load history',
        message: error,
        tone: AppColors.danger,
        action: FilledButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try again'),
        ),
      );
    }

    if (_alerts.isEmpty) {
      return const StatusView(
        icon: Icons.history_rounded,
        title: 'No alerts yet',
        message: 'Every SMS SafeStep sends - a panic alert, an expired timer, '
            'a safe space you left, or an all-clear - is listed here with the '
            'time, the location and who it reached.',
        tone: AppColors.success,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemCount: _alerts.length + 1,
      separatorBuilder: (_, __) => AppSpacing.gapMd,
      itemBuilder: (context, index) {
        if (index == 0) return _buildSummary();
        return _buildAlertCard(_alerts[index - 1]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Alert History'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh history',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.page,
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(),
          ),
        ),
      ),
    );
  }
}

/// A small tinted label used for the delivery and location facts.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: AppStyles.pillDecoration(color),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The full SMS body, plus the map link that went with it.
class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.alert});

  final AlertRecord alert;

  @override
  Widget build(BuildContext context) {
    final link = alert.mapsLink;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(alert.title, style: AppStyles.titleStyle),
            const SizedBox(height: 2),
            Text(
              '${formatAlertTimestamp(alert.createdAt)}  ·  '
              '${alert.deliverySummary}',
              style: AppStyles.captionStyle,
            ),
            AppSpacing.gapLg,
            const Text('MESSAGE SENT', style: AppStyles.overlineStyle),
            AppSpacing.gapSm,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppStyles.sunkenDecoration,
              child: SelectableText(
                alert.message,
                style: AppStyles.bodyStyle.copyWith(height: 1.5),
              ),
            ),
            AppSpacing.gapLg,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: alert.message),
                      );
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ),
                if (link != null) ...[
                  AppSpacing.hGapMd,
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Map link copied.')),
                        );
                      },
                      icon: const Icon(Icons.place_rounded, size: 18),
                      label: const Text('Copy map link'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
