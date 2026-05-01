<<<<<<< HEAD
// auth service
// google sign in uses google_sign_in package — native, not browser
// email otp verification after signup
// stores age and gender in users_public

=======
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';

class AuthService extends ChangeNotifier {
<<<<<<< HEAD
  final SupabaseClient _client = Supabase.instance.client;

  final _googleSignIn = GoogleSignIn(
    // web client id from google cloud console
    // for android: this is the web client id, not the android client id
    // add your SHA-1 fingerprint to google cloud console for android native flow
    serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
=======
  final _client = Supabase.instance.client;
  final _google = GoogleSignIn(
    serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    scopes: ['email', 'profile'],
  );
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)

  bool _isLoading = false;
  String? _error;
  bool _hasUsername = false;
  String? _googleDisplayName;

  bool get isLoading => _isLoading;
  String? get error => _error;
<<<<<<< HEAD

  AuthService() {
    _client.auth.onAuthStateChange.listen((event) {
      AppLogger.info('auth: state changed ${event.event.name}');
      notifyListeners();
    });
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      _error = null;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'something went wrong, try again';
    } finally {
      _setLoading(false);
    }
  }

  // signs up and sends OTP to email — user must verify before proceeding
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'echoproof://auth-callback',
      );
      _error = null;
      // after signup, OTP is sent automatically by supabase
      // navigate to OTP verification screen
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'sign up failed, try again';
    } finally {
      _setLoading(false);
    }
  }

  // verifies OTP sent to email
  Future<bool> verifyEmailOtp({
    required String email,
    required String otp,
  }) async {
    _setLoading(true);
    try {
      await _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.signup,
      );
      _error = null;
      _setLoading(false);
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'verification failed';
      _setLoading(false);
      return false;
    }
  }

  // resends OTP
  Future<void> resendOtp({required String email}) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    } catch (e) {
      AppLogger.error('auth: resend OTP failed', e);
    }
  }

  // native google sign in — uses google_sign_in package
  // shows the native google account picker, not a browser
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // user cancelled
        _setLoading(false);
        notifyListeners();
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) throw Exception('no id token from google');

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      _error = null;
      AppLogger.info('auth: google sign in success');
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'google sign in failed — try again';
      AppLogger.error('auth: google sign in error', e);
    } finally {
      _setLoading(false);
    }
  }

  // saves age and gender to users_public after signup
  Future<void> saveAgeAndGender({
    required int age,
    required String gender,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;

    try {
      await _client.from('users_public').upsert({
        'id': userId,
        'age': age,
        'gender': gender,
      });
    } catch (e) {
      AppLogger.error('auth: save age/gender failed', e);
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _client.auth.signOut();
    notifyListeners();
  }
=======
  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  bool get hasUsername => _hasUsername;
  String? get googleDisplayName => _googleDisplayName;
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> checkUsername() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        _hasUsername = false;
        notifyListeners();
        return;
      }
      final row = await _client
          .from('users_public')
          .select('onboarding_complete')
          .eq('id', userId)
          .maybeSingle();
      final done = row != null ? row['onboarding_complete'] as bool? : null;
      _hasUsername = done == true;
    } catch (e) {
      _hasUsername = false;
    }
    notifyListeners();
  }
<<<<<<< HEAD
=======

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

  Future<void> saveAgeAndGender({
    required int age,
    required String gender,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from('users_private')
          .update({'age': age, 'gender': gender}).eq('id', userId);
    } catch (e) {
      AppLogger.error('auth: save age/gender failed $e');
    }
  }

  Future<void> deleteIncompleteAccount() async {
    // sign out — doesn't delete the auth record
    // the users_public row still exists but onboarding_done is false
    // so router will redirect back to onboarding
    try {
      await _google.signOut();
      await _client.auth.signOut();
      _hasUsername = false;
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
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
}
