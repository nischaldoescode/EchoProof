// auth service
// google sign in uses google_sign_in package — native, not browser
// email otp verification after signup
// stores age and gender in users_public

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';

class AuthService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  final _googleSignIn = GoogleSignIn(
    // web client id from google cloud console
    // for android: this is the web client id, not the android client id
    // add your SHA-1 fingerprint to google cloud console for android native flow
    serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
  );

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
