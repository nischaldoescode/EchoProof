// auth service
// manages authentication state using ChangeNotifier
// screens listen to this via context.watch<AuthService>()
// replaces: auth_provider.dart (riverpod version)

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
    // listen to auth state changes and notify listeners
    _client.auth.onAuthStateChange.listen((event) {
      AppLogger.info('auth: state changed to ${event.event.name}');
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
        email:    email,
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

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    try {
      await _client.auth.signUp(
        email:    email,
        password: password,
      );
      _error = null;
      AppLogger.info('auth: signed up with email');
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'sign up failed, try again';
    } finally {
      _setLoading(false);
    }
  }

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

  Future<void> signOut() async {
    await _client.auth.signOut();
    AppLogger.info('auth: signed out');
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