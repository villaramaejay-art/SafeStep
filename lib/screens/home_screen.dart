import 'package:flutter/material.dart';
import '../models/alert_record.dart';
import '../models/profile.dart';
import '../services/alerts_repository.dart';
import '../services/auth_service.dart';
import '../services/contacts_repository.dart';
import '../services/emergency_service.dart';
import '../services/location_service.dart';
import '../services/safe_spaces_repository.dart';
import '../services/weather_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../utils/text_format.dart';
import '../widgets/alert_countdown_dialog.dart';
import '../widgets/panic_button.dart';

/// Weather plus where it was measured, so the card can say which was used.
class _WeatherReading {
  const _WeatherReading({required this.weather, required this.isLive});

  final SafetyWeather weather;

  /// True when the reading came from the device's GPS position.
  final bool isLive;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onNavigate});

  /// Switches the shell to another tab, so the summary tiles jump straight to
  /// the section they describe.
  final ValueChanged<int> onNavigate;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final WeatherService _weatherService = WeatherService();
  final LocationService _locationService = LocationService();
  final AuthService _authService = AuthService();
  final EmergencyService _emergencyService = EmergencyService();
  final ContactsRepository _contactsRepository = ContactsRepository();
  final SafeSpacesRepository _safeSpacesRepository = SafeSpacesRepository();
  final AlertsRepository _alertsRepository = AlertsRepository();

  /// How long after an alert the stand-down prompt keeps offering itself. Past
  /// this the alert is old news, and the card would only be clutter.
  static const Duration _allClearWindow = Duration(hours: 12);

  late Future<_WeatherReading> _weatherFuture;
  Profile? _profile;
  int? _contactCount;
  int? _safeSpaceCount;
  AlertRecord? _latestAlert;
  bool _isSendingAlert = false;
  bool _isSendingAllClear = false;

  @override
  void initState() {
    super.initState();
    _weatherFuture = _loadWeather();
    _loadProfile();
    _loadCounts();
    _loadLatestAlert();
  }

  bool get _needsAllClear =>
      needsAllClear(_latestAlert, window: _allClearWindow);

  Future<void> _loadLatestAlert() async {
    try {
      final latest = await _alertsRepository.fetchLatest();
      if (mounted) setState(() => _latestAlert = latest);
    } on RepositoryFailure {
      // The dashboard still works without it; the History tab reports why.
    }
  }

  Future<void> _loadProfile() async {
    final profile = await _authService.fetchProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
  }

  /// Counts for the summary tiles. Failures leave the tile showing a dash
  /// rather than blocking the dashboard.
  Future<void> _loadCounts() async {
    try {
      final contacts = await _contactsRepository.fetchAll();
      if (mounted) setState(() => _contactCount = contacts.length);
    } on RepositoryFailure {
      // leave null
    }

    try {
      final spaces = await _safeSpacesRepository.fetchAll();
      if (mounted) setState(() => _safeSpaceCount = spaces.length);
    } on RepositoryFailure {
      // leave null
    }
  }

  /// Uses the device position when available, otherwise the Manila fallback.
  Future<_WeatherReading> _loadWeather() async {
    LocationFix? fix;

    try {
      fix = await _locationService.getCurrentFix();
    } on LocationException {
      fix = null;
    }

    final weather = await _weatherService.fetchCurrentConditions(
      at: fix?.point,
    );

    return _WeatherReading(weather: weather, isLive: fix != null);
  }

  Future<void> _refreshAll() async {
    setState(() {
      _weatherFuture = _loadWeather();
    });
    await Future.wait([_loadProfile(), _loadCounts(), _loadLatestAlert()]);
  }

  /// Sends the panic alert, after a short window in which a mistaken tap can
  /// still be cancelled.
  Future<void> _triggerPanic() async {
    final confirmed = await AlertCountdownDialog.show(
      context,
      title: 'Sending panic alert',
      detail: 'Your emergency contacts will receive an SMS with your name and '
          'current location.',
      cancelLabel: 'Cancel, I am safe',
    );

    if (!confirmed || !mounted) return;

    setState(() => _isSendingAlert = true);

    final AlertOutcome outcome;
    try {
      outcome = await _emergencyService.sendAlert(reason: AlertReason.panic);
    } finally {
      // The button is disabled while this flag is set. If a throw ever left it
      // set, the panic button would stay dead until the app was restarted.
      if (mounted) setState(() => _isSendingAlert = false);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.summary),
        backgroundColor:
            outcome.isSuccess ? AppColors.success : AppColors.danger,
      ),
    );

    // Brings up the stand-down prompt straight away, so the way to close the
    // loop is already on screen once the panic is over.
    await _loadLatestAlert();
  }

  /// Sends the follow-up that tells the contacts the emergency is over.
  ///
  /// Confirmed first: an accidental all-clear tells people to stop worrying,
  /// which is the one mistake here that makes things worse rather than noisier.
  Future<void> _sendAllClear() async {
    final contacts = _contactCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tell your contacts you are safe?'),
        content: Text(
          contacts == null
              ? 'Everyone who received your alert gets a follow-up SMS saying '
                  'the emergency is over.'
              : 'All ${TextFormat.count(contacts, 'contact')} who received '
                  'your alert get a follow-up SMS saying the emergency is '
                  'over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Send all-clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSendingAllClear = true);

    final AlertOutcome outcome;
    try {
      outcome = await _emergencyService.sendAllClear();
    } finally {
      if (mounted) setState(() => _isSendingAllClear = false);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.summary),
        backgroundColor:
            outcome.isSuccess ? AppColors.success : AppColors.danger,
      ),
    );

    // A successful all-clear becomes the latest alert, which retires the card.
    await _loadLatestAlert();
  }

  Future<void> _confirmSignOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          _authService.email == null
              ? 'Your contacts and safe spaces stay saved to your account.'
              : 'Your contacts and safe spaces stay saved to '
                  '${_authService.email}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (shouldSignOut != true) return;

    try {
      // AuthGate listens for the session change and shows the login screen.
      await _authService.signOut();
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message)),
      );
    }
  }

  String get _initials {
    final profile = _profile;
    if (profile == null) return 'SS';

    final first = profile.firstName.isEmpty ? '' : profile.firstName[0];
    final last = profile.lastName.isEmpty ? '' : profile.lastName[0];
    final initials = '$first$last'.toUpperCase();

    return initials.isEmpty ? 'SS' : initials;
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildGreeting() {
    final profile = _profile;

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.primarySoft, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Text(
            _initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile == null ? 'Welcome back' : 'Hi ${profile.firstName}',
                style: AppStyles.displayStyle.copyWith(fontSize: 22),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                profile == null ? 'Your safety plan is active.' : profile.phone,
                style: AppStyles.captionStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _confirmSignOut,
          icon: const Icon(Icons.logout_rounded),
          tooltip: 'Sign out',
        ),
      ],
    );
  }

  /// The open loop: an alert went out and the contacts have not been told it is
  /// over. Sits above everything else because nothing on this screen matters
  /// more than the people still worrying.
  Widget _buildAllClearCard() {
    final alert = _latestAlert!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppStyles.statusDecoration(AppColors.danger),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppSpacing.medium,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your contacts were alerted',
                      style: AppStyles.labelStyle.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${alert.title}  ·  '
                      '${formatRelativeTime(alert.createdAt)}',
                      style: AppStyles.captionStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.gapMd,
          Text(
            'They will keep worrying until they hear from you.',
            style: AppStyles.captionStyle,
          ),
          AppSpacing.gapMd,
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                  onPressed: _isSendingAllClear ? null : _sendAllClear,
                  icon: _isSendingAllClear
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.verified_rounded, size: 18),
                  label: Text(
                    _isSendingAllClear ? 'Sending...' : "I'm safe now",
                  ),
                ),
              ),
              AppSpacing.hGapSm,
              TextButton(
                onPressed: () => widget.onNavigate(4),
                child: const Text('History'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherCard() {
    return FutureBuilder<_WeatherReading>(
      future: _weatherFuture,
      builder: (context, snapshot) {
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final reading = snapshot.data;
        final hasError = snapshot.hasError;

        final String detail;
        if (hasError) {
          detail = 'Weather data is unavailable right now.';
        } else if (isLoading || reading == null) {
          detail = 'Getting weather for your location...';
        } else {
          final weather = reading.weather;
          detail = '${weather.temperature.toStringAsFixed(1)} C  -  '
              '${weather.precipitation.toStringAsFixed(1)} mm rain';
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: AppStyles.cardDecoration,
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: AppStyles.iconTileDecoration(),
                child: Icon(
                  hasError ? Icons.cloud_off_rounded : Icons.wb_cloudy_rounded,
                  color: AppColors.primary,
                  size: 23,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            hasError || reading == null
                                ? 'Local conditions'
                                : reading.weather.condition,
                            style: AppStyles.sectionTitleStyle,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (reading != null) ...[
                          AppSpacing.hGapSm,
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: AppStyles.pillDecoration(
                              reading.isLive
                                  ? AppColors.success
                                  : AppColors.textTertiary,
                            ),
                            child: Text(
                              reading.isLive ? 'Live GPS' : 'Manila',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                                color: reading.isLive
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(detail, style: AppStyles.captionStyle),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// A count plus a shortcut. With a permanent bottom bar these tiles are not
  /// there to navigate - they are there to say what is set up.
  Widget _buildSummaryTile({
    required IconData icon,
    required String label,
    required int? count,
    required String unit,
    required int tabIndex,
  }) {
    final isEmpty = count == 0;

    return Expanded(
      child: Material(
        color: AppColors.surface,
        borderRadius: AppSpacing.large,
        child: InkWell(
          borderRadius: AppSpacing.large,
          onTap: () => widget.onNavigate(tabIndex),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: AppSpacing.large,
              border: Border.all(
                color: isEmpty ? AppColors.warning.withValues(alpha: 0.45)
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                AppSpacing.gapMd,
                Text(
                  count == null ? '-' : '$count',
                  style: AppStyles.displayStyle.copyWith(fontSize: 24),
                ),
                Text(
                  count == 1 ? unit : '${unit}s',
                  style: AppStyles.captionStyle.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: AppStyles.captionStyle.copyWith(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A soft ring behind the button, so it reads as the centre of the screen
  /// rather than one more control on it.
  Widget _haloRing(double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withValues(alpha: opacity),
      ),
    );
  }

  /// Says, in one line, whether pressing the button will actually reach anyone.
  ///
  /// This used to be a card of its own above the fold. It belongs here: the
  /// readiness of the button is a fact about the button.
  Widget _buildReadinessLine() {
    final contacts = _contactCount;
    final hasContacts = (contacts ?? 0) > 0;

    late final Color tone;
    late final IconData icon;
    late final String message;

    if (_isSendingAlert) {
      tone = AppColors.primary;
      icon = Icons.podcasts_rounded;
      message = 'Sending your alert...';
    } else if (contacts == null) {
      tone = AppColors.textTertiary;
      icon = Icons.shield_outlined;
      message = 'Checking your safety plan';
    } else if (!hasContacts) {
      tone = AppColors.warning;
      icon = Icons.person_add_alt_1_rounded;
      message = 'Add a contact - nobody would be alerted';
    } else {
      tone = AppColors.success;
      icon = Icons.verified_user_rounded;
      message = contacts == 1
          ? 'Ready - 1 contact will be alerted'
          : 'Ready - $contacts contacts will be alerted';
    }

    final line = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: AppStyles.pillDecoration(tone),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tone),
          AppSpacing.hGapSm,
          Flexible(
            child: Text(
              message,
              style: AppStyles.captionStyle.copyWith(
                color: tone,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    // Without contacts the line is not just a status, it is the fix - so it
    // takes you to the screen that resolves it.
    return hasContacts || _isSendingAlert || contacts == null
        ? line
        : GestureDetector(onTap: () => widget.onNavigate(1), child: line);
  }

  /// The panic button, centred and given room. It is the reason the app exists,
  /// so it is the first thing on the screen and the only thing at this size.
  Widget _buildPanicHero() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              _haloRing(272, 0.05),
              _haloRing(228, 0.07),
              PanicButton(
                size: 190,
                onPressed: _isSendingAlert ? () {} : _triggerPanic,
              ),
            ],
          ),
          AppSpacing.gapLg,
          _buildReadinessLine(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreeting(),

                // An unanswered alert outranks everything, including the
                // button: the contacts are still waiting.
                if (_needsAllClear) ...[
                  AppSpacing.gapXl,
                  _buildAllClearCard(),
                ],

                AppSpacing.gapXxl,
                _buildPanicHero(),
                AppSpacing.gapXxl,

                const Text('YOUR SETUP', style: AppStyles.overlineStyle),
                AppSpacing.gapMd,
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummaryTile(
                        icon: Icons.contacts_rounded,
                        label: 'Emergency contacts',
                        count: _contactCount,
                        unit: 'contact',
                        tabIndex: 1,
                      ),
                      AppSpacing.hGapMd,
                      _buildSummaryTile(
                        icon: Icons.location_on_rounded,
                        label: 'Safe spaces',
                        count: _safeSpaceCount,
                        unit: 'zone',
                        tabIndex: 2,
                      ),
                    ],
                  ),
                ),
                AppSpacing.gapLg,
                _buildWeatherCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
