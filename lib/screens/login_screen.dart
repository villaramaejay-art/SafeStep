import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../widgets/info_banner.dart';

/// One password requirement, named so the checklist shown to the user and the
/// validator that blocks submission can never drift apart.
enum _PasswordRule {
  length('At least 8 characters'),
  upper('One uppercase letter'),
  lower('One lowercase letter'),
  digit('One number'),
  special('One special character');

  const _PasswordRule(this.label);

  final String label;

  bool isMetBy(String password) {
    switch (this) {
      case _PasswordRule.length:
        return password.length >= 8;
      case _PasswordRule.upper:
        return RegExp(r'[A-Z]').hasMatch(password);
      case _PasswordRule.lower:
        return RegExp(r'[a-z]').hasMatch(password);
      case _PasswordRule.digit:
        return RegExp(r'[0-9]').hasMatch(password);
      case _PasswordRule.special:
        return RegExp(r'[^A-Za-z0-9]').hasMatch(password);
    }
  }
}

/// Strips a typed phone number down to digits (plus a leading country code),
/// the same way a contact's number is cleaned before it is texted. Doing it
/// once here means the database never holds "0917 123 4567" next to
/// "+63-917-123-4567" for what is really the same number.
String _normalizePhone(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  return trimmed.startsWith('+') ? '+$digits' : digits;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final AuthService _authService = AuthService();

  // One key per field, in on-screen order, so a failed submit can scroll
  // straight to whichever one is actually wrong - including one scrolled out
  // of view, which otherwise fails exactly as silently as a mistaken tap.
  final GlobalKey _firstNameFieldKey = GlobalKey();
  final GlobalKey _lastNameFieldKey = GlobalKey();
  final GlobalKey _phoneFieldKey = GlobalKey();
  final GlobalKey _emailFieldKey = GlobalKey();
  final GlobalKey _passwordFieldKey = GlobalKey();
  final GlobalKey _confirmPasswordFieldKey = GlobalKey();

  bool _isRegistering = false;
  bool _isBusy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _error;
  String? _notice;

  // A one-time entrance for the first screen anyone sees, so the app opens
  // with some life in it rather than snapping straight to a static form.
  late final AnimationController _entranceController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  late final Animation<double> _entranceFade = CurvedAnimation(
    parent: _entranceController,
    curve: Curves.easeOut,
  );

  late final Animation<Offset> _entranceSlide = Tween(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(_entranceFade);

  @override
  void dispose() {
    _entranceController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- Validation -----------------------------------------------------------

  String? _validateName(String? value, String label) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter your $label.';
    if (name.length < 2) return 'Your $label looks too short.';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Enter your phone number.';

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 7) return 'Enter at least 7 digits.';
    if (!RegExp(r'^\+?[0-9()\s-]+$').hasMatch(phone)) {
      return 'Use digits, spaces, dashes or a leading +.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Enter your email address.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// Sign-in only checks that something was typed - an account made before
  /// these rules existed can still have a shorter password, and the server,
  /// not this form, is the one that actually knows if it is correct.
  /// Registration holds the line on every rule in [_PasswordRule].
  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    if (!_isRegistering) return null;

    final allMet = _PasswordRule.values.every((rule) => rule.isMetBy(password));
    return allMet ? null : 'Meet every requirement listed below.';
  }

  String? _validateConfirmPassword(String? value) {
    if (!_isRegistering) return null;
    final confirm = value ?? '';
    if (confirm.isEmpty) return 'Re-enter your password.';
    if (confirm != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  /// Scrolls to the first field that is still wrong, so a submit that fails
  /// validation always points at something - even a field currently scrolled
  /// off the bottom, which previously failed in total silence.
  Future<void> _scrollToFirstError() async {
    final entries = <(GlobalKey, String? Function())>[
      if (_isRegistering)
        (
          _firstNameFieldKey,
          () => _validateName(_firstNameController.text, 'first name'),
        ),
      if (_isRegistering)
        (
          _lastNameFieldKey,
          () => _validateName(_lastNameController.text, 'last name'),
        ),
      if (_isRegistering)
        (_phoneFieldKey, () => _validatePhone(_phoneController.text)),
      (_emailFieldKey, () => _validateEmail(_emailController.text)),
      (_passwordFieldKey, () => _validatePassword(_passwordController.text)),
      if (_isRegistering)
        (
          _confirmPasswordFieldKey,
          () => _validateConfirmPassword(_confirmPasswordController.text),
        ),
    ];

    for (final (key, validate) in entries) {
      if (validate() == null) continue;

      final context = key.currentContext;
      if (context != null) {
        await Scrollable.ensureVisible(
          context,
          alignment: 0.15,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      }
      return;
    }
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.vibrate();
      await _scrollToFirstError();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix the highlighted field.')),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _notice = null;
    });

    // Normalized once here so the database never holds two spellings of the
    // same email or the same phone number.
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    try {
      if (_isRegistering) {
        final signedIn = await _authService.signUp(
          email: email,
          password: password,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phone: _normalizePhone(_phoneController.text),
        );

        if (!mounted) return;

        // A confirmed-email project returns no session; AuthGate would not
        // move, so say why instead of leaving the user on a dead button.
        if (!signedIn) {
          setState(() {
            _isRegistering = false;
            _notice =
                'Account created. Check $email for the confirmation '
                'link, then sign in.';
          });
        }
      } else {
        await _authService.signIn(email: email, password: password);
      }
      // On success AuthGate swaps this screen for the dashboard.
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _setMode(bool registering) {
    if (registering == _isRegistering || _isBusy) return;

    setState(() {
      _isRegistering = registering;
      _error = null;
      _notice = null;
      _confirmPasswordController.clear();
      // Registration-only fields would otherwise keep stale validation errors.
      _formKey.currentState?.reset();
    });
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildBrand() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: AppSpacing.large,
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Image.asset('assets/branding/safestep_mark.png'),
          ),
          AppSpacing.gapLg,
          Text(
            'SafeStep',
            style: AppStyles.displayStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Reliable emergency support, made simple.',
            style: AppStyles.bodyMutedStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: false,
            label: Text('Sign in'),
            icon: Icon(Icons.login_rounded, size: 16),
          ),
          ButtonSegment(
            value: true,
            label: Text('Create account'),
            icon: Icon(Icons.person_add_alt_1_rounded, size: 16),
          ),
        ],
        selected: {_isRegistering},
        onSelectionChanged: (selection) => _setMode(selection.first),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(label, style: AppStyles.overlineStyle),
    );
  }

  List<Widget> _buildRegistrationFields() {
    return [
      _buildSectionLabel('YOUR DETAILS'),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: _firstNameFieldKey,
              controller: _firstNameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: !_isBusy,
              validator: (value) => _validateName(value, 'first name'),
              decoration: const InputDecoration(
                labelText: 'First name',
                hintText: 'Maria',
              ),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: TextFormField(
              key: _lastNameFieldKey,
              controller: _lastNameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              enabled: !_isBusy,
              validator: (value) => _validateName(value, 'last name'),
              decoration: const InputDecoration(
                labelText: 'Last name',
                hintText: 'Dela Cruz',
              ),
            ),
          ),
        ],
      ),
      AppSpacing.gapLg,
      TextFormField(
        key: _phoneFieldKey,
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        enabled: !_isBusy,
        validator: _validatePhone,
        decoration: const InputDecoration(
          labelText: 'Phone number',
          hintText: '+63 917 123 4567',
          prefixIcon: Icon(Icons.phone_outlined, size: 20),
        ),
      ),
      AppSpacing.gapXl,
      _buildSectionLabel('ACCOUNT'),
    ];
  }

  Widget _buildPasswordRequirements() {
    return AnimatedBuilder(
      animation: _passwordController,
      builder: (context, _) {
        final password = _passwordController.text;
        if (password.isEmpty) return const SizedBox.shrink();

        final metCount = _PasswordRule.values
            .where((rule) => rule.isMetBy(password))
            .length;
        final total = _PasswordRule.values.length;

        final Color tone;
        final String label;
        if (metCount <= 2) {
          tone = AppColors.danger;
          label = 'Weak';
        } else if (metCount == 3) {
          tone = AppColors.warning;
          label = 'Fair';
        } else if (metCount == 4) {
          tone = AppColors.primary;
          label = 'Good';
        } else {
          tone = AppColors.success;
          label = 'Strong';
        }

        return Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: AppSpacing.rounded,
                      child: LinearProgressIndicator(
                        value: metCount / total,
                        minHeight: 6,
                        backgroundColor: AppColors.border,
                        color: tone,
                      ),
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Text(
                    label,
                    style: TextStyle(
                      color: tone,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              AppSpacing.gapSm,
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final rule in _PasswordRule.values)
                    _buildRuleRow(rule, rule.isMetBy(password)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRuleRow(_PasswordRule rule, bool met) {
    final color = met ? AppColors.success : AppColors.textTertiary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          rule.label,
          style: TextStyle(
            fontSize: 11.5,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          child: FadeTransition(
            opacity: _entranceFade,
            child: SlideTransition(
              position: _entranceSlide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBrand(),
                  AppSpacing.gapXxl,
                  Text(
                    _isRegistering ? 'Create your account' : 'Welcome back',
                    style: AppStyles.titleStyle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isRegistering
                        ? 'Your details, contacts and safe spaces are saved to '
                              'your account.'
                        : 'Sign in to reach your safety network and emergency plan.',
                    style: AppStyles.bodyMutedStyle,
                  ),
                  AppSpacing.gapXl,
                  _buildModeToggle(),
                  AppSpacing.gapXl,
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    decoration: AppStyles.cardDecoration,
                    child: Form(
                      key: _formKey,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      child: Column(
                        children: [
                          if (_error != null)
                            InfoBanner(
                              message: _error!,
                              icon: Icons.error_outline_rounded,
                              color: AppColors.danger,
                            ),
                          if (_notice != null)
                            InfoBanner(
                              message: _notice!,
                              icon: Icons.mark_email_unread_outlined,
                              color: AppColors.primary,
                            ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            alignment: Alignment.topCenter,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_isRegistering)
                                  ..._buildRegistrationFields(),
                                TextFormField(
                                  key: _emailFieldKey,
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  enabled: !_isBusy,
                                  validator: _validateEmail,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                    hintText: 'you@example.com',
                                    prefixIcon: Icon(
                                      Icons.mail_outline_rounded,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                AppSpacing.gapLg,
                                TextFormField(
                                  key: _passwordFieldKey,
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  textInputAction: _isRegistering
                                      ? TextInputAction.next
                                      : TextInputAction.done,
                                  enabled: !_isBusy,
                                  validator: _validatePassword,
                                  onFieldSubmitted: _isRegistering
                                      ? null
                                      : (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                      size: 20,
                                    ),
                                    helperText: _isRegistering
                                        ? 'At least 8 characters, mixed case, a '
                                              'number and a symbol'
                                        : null,
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        size: 20,
                                      ),
                                      tooltip: _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                    ),
                                  ),
                                ),
                                if (_isRegistering)
                                  _buildPasswordRequirements(),
                                if (_isRegistering) ...[
                                  AppSpacing.gapLg,
                                  TextFormField(
                                    key: _confirmPasswordFieldKey,
                                    controller: _confirmPasswordController,
                                    obscureText: _obscureConfirmPassword,
                                    textInputAction: TextInputAction.done,
                                    enabled: !_isBusy,
                                    validator: _validateConfirmPassword,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                      labelText: 'Confirm password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outline_rounded,
                                        size: 20,
                                      ),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                          () => _obscureConfirmPassword =
                                              !_obscureConfirmPassword,
                                        ),
                                        icon: Icon(
                                          _obscureConfirmPassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          size: 20,
                                        ),
                                        tooltip: _obscureConfirmPassword
                                            ? 'Show password'
                                            : 'Hide password',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          AppSpacing.gapXl,
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isBusy ? null : _submit,
                              child: _isBusy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _isRegistering ? 'Register' : 'Sign In',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
