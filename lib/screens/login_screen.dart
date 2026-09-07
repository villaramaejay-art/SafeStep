import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_styles.dart';
import '../widgets/info_banner.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Supabase's own floor is 6; SafeStep asks for more.
  static const int _minPasswordLength = 8;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isRegistering = false;
  bool _isBusy = false;
  bool _obscurePassword = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    if (password.length < _minPasswordLength) {
      return 'Use at least $_minPasswordLength characters.';
    }
    return null;
  }

  // --- Actions --------------------------------------------------------------

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isBusy = true;
      _error = null;
      _notice = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_isRegistering) {
        final signedIn = await _authService.signUp(
          email: email,
          password: password,
          firstName: _firstNameController.text.trim(),
          lastName: _lastNameController.text.trim(),
          phone: _phoneController.text.trim(),
        );

        if (!mounted) return;

        // A confirmed-email project returns no session; AuthGate would not
        // move, so say why instead of leaving the user on a dead button.
        if (!signedIn) {
          setState(() {
            _isRegistering = false;
            _notice = 'Account created. Check $email for the confirmation '
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

  void _toggleMode() {
    setState(() {
      _isRegistering = !_isRegistering;
      _error = null;
      _notice = null;
      // Registration-only fields would otherwise keep stale validation errors.
      _formKey.currentState?.reset();
    });
  }

  // --- Widgets --------------------------------------------------------------

  Widget _buildBrand() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: AppSpacing.large,
            gradient: const LinearGradient(
              colors: [AppColors.primarySoft, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.shield_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        AppSpacing.gapLg,
        const Text('SafeStep', style: AppStyles.displayStyle),
        const SizedBox(height: 4),
        const Text(
          'Reliable emergency support, made simple.',
          style: AppStyles.bodyMutedStyle,
        ),
      ],
    );
  }

  List<Widget> _buildRegistrationFields() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
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
      AppSpacing.gapLg,
    ];
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
                      if (_isRegistering) ..._buildRegistrationFields(),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enabled: !_isBusy,
                        validator: _validateEmail,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          hintText: 'you@example.com',
                          prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                        ),
                      ),
                      AppSpacing.gapLg,
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        enabled: !_isBusy,
                        validator: _validatePassword,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                          ),
                          helperText: _isRegistering
                              ? 'At least $_minPasswordLength characters'
                              : null,
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
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
                              : Text(_isRegistering ? 'Register' : 'Sign In'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              AppSpacing.gapLg,
              Center(
                child: TextButton(
                  onPressed: _isBusy ? null : _toggleMode,
                  child: Text(
                    _isRegistering
                        ? 'Already have an account? Sign in'
                        : 'New to SafeStep? Create an account',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
