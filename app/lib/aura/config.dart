/// Build-time settings. Pass them when building:
///
///   flutter run --dart-define-from-file=config.json
///
/// with config.json (see config.example.json):
///   { "SUPABASE_URL": "https://xyz.supabase.co", "SUPABASE_ANON_KEY": "…", "API_URL": "https://aura-api.onrender.com" }
///
/// Without them the app runs as an offline demo on built-in sample data, so it
/// can still be shown and tested before the servers are set up.
class AuraConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const apiUrl = String.fromEnvironment('API_URL');

  /// Deep link that Google sign-in, email verification and password reset return to.
  /// Must be listed in Supabase → Authentication → URL Configuration → Redirect URLs.
  static const authRedirect = String.fromEnvironment('AUTH_REDIRECT', defaultValue: 'aurabyhs://login-callback');

  static bool get live => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty && apiUrl.isNotEmpty;
}
