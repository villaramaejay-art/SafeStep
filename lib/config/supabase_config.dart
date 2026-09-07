/// Supabase credentials, supplied at build time so they never enter git.
///
/// Run with:
///   flutter run \
///     --dart-define=SUPABASE_URL=https_//PROJECT.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=YOUR_KEY
///
/// Supabase renamed the "anon public" key to "publishable key"; either name
/// works here, and either value works with the SDK.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static String get key => _anonKey.isNotEmpty ? _anonKey : _publishableKey;

  static bool get isConfigured => url.isNotEmpty && key.isNotEmpty;

  static const String missingMessage =
      'Supabase is not configured.\n\n'
      'Pass your project credentials when you launch the app:\n\n'
      '  flutter run \\\n'
      '    --dart-define=SUPABASE_URL=YOUR_PROJECT_URL \\\n'
      '    --dart-define=SUPABASE_ANON_KEY=YOUR_KEY\n\n'
      'Both values live in Supabase under Project Settings -> API.';
}
