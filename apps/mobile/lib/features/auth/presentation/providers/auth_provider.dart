// auth service
// manages authentication state using changenotifier
// replaces auth_provider.dart (riverpod version)
// screens access via context.watch<AuthService>() and context.read<AuthService>()

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';

class AuthService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  AuthService() {
    // listen to supabase auth state changes and notify all listeners
    _client.auth.onAuthStateChange.listen((event) {
      AppLogger.info('auth: state changed ${event.event.name}');
      notifyListeners();
    });
  }

  // signs in with email and password
  // sets error on failure, navigates automatically via auth state listener
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
      AppLogger.info('auth: signed in with email');
    } on AuthException catch (e) {
      _error = e.message;
      AppLogger.error('auth: sign in failed', e);
    } catch (e) {
      _error = 'something went wrong, try again';
      AppLogger.error('auth: unexpected sign in error', e);
    } finally {
      _setLoading(false);
    }
  }

  // creates a new account with email and password
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
      );
      _error = null;
      AppLogger.info('auth: signed up with email');
    } on AuthException catch (e) {
      _error = e.message;
      AppLogger.error('auth: sign up failed', e);
    } catch (e) {
      _error = 'sign up failed, try again';
      AppLogger.error('auth: unexpected sign up error', e);
    } finally {
      _setLoading(false);
    }
  }

  // opens google oauth flow — completes via deep link redirect
  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'echoproof://auth-callback',
      );
      _error = null;
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'google sign in failed';
    } finally {
      _setLoading(false);
    }
  }

  // signs out and clears local session
  Future<void> signOut() async {
    await _client.auth.signOut();
    AppLogger.info('auth: signed out');
    notifyListeners();
  }

  // clears the current error — call after showing error snackbar
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
