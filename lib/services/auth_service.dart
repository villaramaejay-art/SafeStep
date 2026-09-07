import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';

/// Raised for problems worth showing the user verbatim.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// Email/password authentication backed by Supabase Auth.
class AuthService {
  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentSession != null;
  String? get email => currentUser?.email;

  /// Emits on sign-in, sign-out, and token refresh.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (error) {
      throw AuthFailure(_readable(error));
    }
  }

  /// Creates the account. The name and phone travel as sign-up metadata; a
  /// database trigger copies them into `profiles` in the same transaction, so
  /// an account cannot exist without its details.
  ///
  /// Returns true when the account is usable immediately; false when Supabase
  /// is configured to require email confirmation first.
  Future<bool> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone,
        },
      );
      return response.session != null;
    } on AuthException catch (error) {
      throw AuthFailure(_readable(error));
    }
  }

  /// The last profile read, keyed by account.
  ///
  /// An emergency alert needs the user's name for the SMS, and a round trip to
  /// Postgres to fetch a name that never changes is time the alert does not
  /// have - and a call that fails outright when there is no data, even though
  /// SMS itself needs none. The dashboard loads the profile at sign-in, so by
  /// the time the panic button is pressed this is already warm.
  static final Map<String, Profile> _profileCache = {};

  /// The signed-in account's profile row, or null if it has none.
  Future<Profile?> fetchProfile({bool refresh = false}) async {
    final id = currentUser?.id;
    if (id == null) return null;

    if (!refresh) {
      final cached = _profileCache[id];
      if (cached != null) return cached;
    }

    try {
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (row == null) return null;

      final profile = Profile.fromMap(row);
      _profileCache[id] = profile;
      return profile;
    } on PostgrestException {
      return _profileCache[id];
    }
  }

  Future<void> signOut() async {
    // Keyed by account id, so it could not leak across users - but a signed-out
    // session should not keep anyone's name in memory either.
    _profileCache.clear();

    try {
      await _client.auth.signOut();
    } on AuthException catch (error) {
      throw AuthFailure(_readable(error));
    }
  }

  String _readable(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'That email and password do not match an account.';
    }
    if (message.contains('already registered')) {
      return 'That email already has an account. Try signing in instead.';
    }
    if (message.contains('email not confirmed')) {
      return 'Confirm your email address first, then sign in.';
    }
    // Supabase's built-in mailer allows only a couple of messages per hour,
    // which registration hits quickly while email confirmation is enabled.
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many sign-up emails were sent from this project. Wait an '
          'hour, or turn off "Confirm email" in Supabase so no email is '
          'needed.';
    }
    if (message.contains('signups not allowed') ||
        message.contains('signup is disabled')) {
      return 'New sign-ups are disabled for this project.';
    }
    if (message.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    return error.message;
  }
}
