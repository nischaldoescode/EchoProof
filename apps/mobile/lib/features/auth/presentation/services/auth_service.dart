import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';

class AuthService extends ChangeNotifier {
  final _client = Supabase.instance.client;
  final _google = GoogleSignIn(
    serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    scopes: ['email', 'profile'],
  );

  bool _isLoading = false;
  bool _hasUsernameChecked = false;
  String? _error;
  bool _hasUsername = false;
  String? _googleDisplayName;

  bool get isLoading => _isLoading;
  String? get error => _error;
  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  bool get hasUsername => _hasUsername;

  /// True after at least one successful DB check has completed.
  /// The router uses this to avoid redundant network calls on every
  /// navigation event.
  bool get hasUsernameChecked => _hasUsernameChecked;
  String? get googleDisplayName => _googleDisplayName;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Called after onboarding completion to immediately mark the user as having
  // a username without a round-trip to the DB. Prevents redirect loops when
  // the DB write succeeds but the router re-evaluates before the next check.
  void markOnboardingComplete() {
    _hasUsername = true;
    _hasUsernameChecked = true;
    notifyListeners();
  }

  Future<void> checkUsername() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        _hasUsername = false;
        _hasUsernameChecked = true;
        notifyListeners();
        return;
      }
      final row = await _client
          .from('users_public')
          .select('onboarding_complete, username')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        // Row doesn't exist yet — trigger may be slow, wait and retry once
        await Future.delayed(const Duration(milliseconds: 800));
        final retryRow = await _client
            .from('users_public')
            .select('onboarding_complete, username')
            .eq('id', userId)
            .maybeSingle();
        final done = retryRow?['onboarding_complete'] as bool? ?? false;
        _hasUsername = done == true;
      } else {
        final done = row['onboarding_complete'] as bool? ?? false;
        _hasUsername = done == true;
      }
      _hasUsernameChecked = true;
    } catch (e) {
      _hasUsername = false;
      _hasUsernameChecked = true;
    }
    notifyListeners();
  }

  Future<bool> sendOtp({required String email}) async {
    _setLoading(true);
    _error = null;
    try {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        emailRedirectTo: null,
      );
      AppLogger.info('auth: OTP sent to $email');
      _setLoading(false);
      return true;
    } on AuthException catch (e) {
      _error = _friendly(e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> verifyOtp({
    required String email,
    required String otp,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      final res = await _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );
      if (res.user == null) {
        _error = 'Verification failed. Try again.';
        _setLoading(false);
        return false;
      }
      AppLogger.info('auth: OTP verified ${res.user!.id}');
      await checkUsername();
      _setLoading(false);
      return true;
    } on AuthException catch (e) {
      _error = _friendly(e.message);
      _setLoading(false);
      return false;
    }
  }

  Future<bool> resendOtp({required String email}) => sendOtp(email: email);

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _error = null;
    try {
      await _google.signOut();
      final googleUser = await _google.signIn();
      if (googleUser == null) {
        AppLogger.info('auth: Google sign in cancelled by user');
        _setLoading(false);
        return false;
      }

      _googleDisplayName = googleUser.displayName;
      AppLogger.info('auth: Google user selected: ${googleUser.email}');

      final auth = await googleUser.authentication;
      final idToken = auth.idToken;
      final accessToken = auth.accessToken;

      if (idToken == null) {
        AppLogger.error(
            'auth: Google idToken is null — serverClientId may be wrong');
        _error = 'Google sign in failed. Please try again.';
        _setLoading(false);
        return false;
      }

      AppLogger.info('auth: Got Google idToken, signing in with Supabase');

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      AppLogger.info('auth: Supabase sign in successful, checking username');

      // retry mechanism to handle trigger delay
      for (int i = 0; i < 3; i++) {
        await checkUsername();
        if (_hasUsername) break;

        AppLogger.info('auth: username not ready, retrying... ($i)');
        await Future.delayed(const Duration(milliseconds: 300));
      }

      AppLogger.info('auth: final hasUsername=$_hasUsername');

      _setLoading(false);
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      AppLogger.error(
          'auth: AuthException during Google sign in: ${e.message}');
      _error = _friendly(e.message);
      _setLoading(false);
      return false;
    } catch (e, stack) {
      AppLogger.error('auth: Google sign in error: $e\n$stack');
      _error = 'Google sign in failed. Please try again.';
      _setLoading(false);
      return false;
    }
  }

// saves age, dob, and gender to users_public after initial profile setup
  Future<void> saveAgeAndGender({
    required int age,
    required String gender,
    required DateTime dateOfBirth,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    await Supabase.instance.client.from('users_public').update({
      'age': age,
      'gender': gender,
      // stored as yyyy-mm-dd — postgres date type
      'date_of_birth': '${dateOfBirth.year.toString().padLeft(4, '0')}-'
          '${dateOfBirth.month.toString().padLeft(2, '0')}-'
          '${dateOfBirth.day.toString().padLeft(2, '0')}',
    }).eq('id', userId);
  }

  Future<void> deleteIncompleteAccount() async {
    try {
      await _google.signOut();
      await _client.auth.signOut();
      _hasUsername = false;
      _hasUsernameChecked = false;
      _googleDisplayName = null;
      notifyListeners();
    } catch (e) {
      AppLogger.error('auth: sign out failed $e');
    }
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
      await _client.auth.signOut();
      _hasUsername = false;
      _hasUsernameChecked = false;
      _googleDisplayName = null;
      AppLogger.info('auth: signed out');
      notifyListeners();
    } catch (e) {
      AppLogger.error('auth: sign out failed $e');
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  String _friendly(String message) {
    final m = message.toLowerCase();
    if (m.contains('otp') && m.contains('invalid'))
      return 'Incorrect code. Try again.';
    if (m.contains('expired')) return 'Code expired. Request a new one.';
    if (m.contains('invalid_credentials'))
      return 'Incorrect email or password.';
    if (m.contains('user_already_exists'))
      return 'Account already exists. Sign in instead.';
    if (m.contains('email_not_confirmed'))
      return 'Please verify your email first.';
    if (m.contains('too_many_requests'))
      return 'Too many attempts. Wait a moment.';
    if (m.contains('network')) return 'Network error. Check your connection.';
    return message;
  }
}
