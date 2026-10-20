import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

/// Customer sign-in through Supabase Auth: Google, or email + password with an
/// email verification link, and password reset by email.
class AuthService {
  AuthService._();
  static final AuthService i = AuthService._();

  SupabaseClient get _sb => Supabase.instance.client;

  static Future<void> init() async {
    await Supabase.initialize(url: AuraConfig.supabaseUrl, publishableKey: AuraConfig.supabaseAnonKey);
  }

  Session? get session => AuraConfig.live ? _sb.auth.currentSession : null;
  User? get user => session?.user;
  bool get signedIn => session != null;
  bool get emailVerified => user?.emailConfirmedAt != null;
  Stream<AuthState> get changes => _sb.auth.onAuthStateChange;

  String? get _redirect => kIsWeb ? null : AuraConfig.authRedirect;

  /// Opens Google's account chooser; the app is signed in when it returns.
  Future<void> google() async {
    await _sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: _redirect, authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
  }

  Future<void> signIn(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  /// Creates the account and emails a verification link. Returns true when the
  /// project signs people in straight away (email confirmation turned off).
  Future<bool> signUp({required String name, required String email, required String password}) async {
    try {
      final r = await _sb.auth.signUp(email: email.trim().toLowerCase(), password: password, data: {'full_name': name.trim()}, emailRedirectTo: _redirect);
      return r.session != null;
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  Future<void> resendVerification(String email) async {
    try {
      await _sb.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase(), emailRedirectTo: _redirect);
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _sb.auth.resetPasswordForEmail(email.trim().toLowerCase(), redirectTo: kIsWeb ? null : 'aurabyhs://reset-password');
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  Future<void> setNewPassword(String password) async {
    try {
      await _sb.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    }
  }

  Future<void> signOut() async {
    if (AuraConfig.live) await _sb.auth.signOut();
  }

  static String _friendly(String m) {
    final s = m.toLowerCase();
    if (s.contains('invalid login')) return 'That email or password is not right.';
    if (s.contains('email not confirmed')) return 'Please verify your email first — tap the link we sent you.';
    if (s.contains('already registered') || s.contains('already been registered')) return 'An account with this email already exists. Sign in instead.';
    if (s.contains('password should be')) return 'Use a password of at least 6 characters.';
    if (s.contains('rate limit')) return 'Too many tries. Please wait a minute and try again.';
    return m;
  }
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
