import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';

class AuthService extends ChangeNotifier {
  static const _settingsBox = 'app_settings';
  static const _onboardingDoneKey = 'onboarding_done';
  static const _onboardingStepKey = 'onboarding_step';
  static const _onboardingUsernameSetKey = 'onboarding_username_set';
  static const _lastSignedInUserIdKey = 'last_signed_in_user_id';
  static const _authRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: 'echoproof://auth-callback',
  );

  final _client = Supabase.instance.client;
  final _google = GoogleSignIn(
    serverClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    scopes: ['email', 'profile'],
  );
  late final StreamSubscription<AuthState> _authSub;

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
  bool _needsAgeGender = false;
  bool get needsAgeGender => _needsAgeGender;

  AuthService() {
    _authSub = _client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.initialSession ||
          data.event == AuthChangeEvent.userUpdated) {
        unawaited(_syncSignedInUser(data.session?.user));
      } else if (data.event == AuthChangeEvent.signedOut) {
        _hasUsername = false;
        _hasUsernameChecked = false;
        _needsAgeGender = false;
        _googleDisplayName = null;
        notifyListeners();
      }
    });
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // marks the user as ready after onboarding writes successfully
  void markOnboardingComplete() {
    _hasUsername = true;
    _hasUsernameChecked = true;
    _needsAgeGender = false;
    notifyListeners();
  }

  // prevents concurrent profile checks during router refresh bursts
  bool _checkingUsername = false;

  Future<void> checkUsername() async {
    if (_checkingUsername) return;
    _checkingUsername = true;

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        _hasUsername = false;
        _hasUsernameChecked = true;
        _needsAgeGender = false;
        _checkingUsername = false;
        notifyListeners();
        return;
      }

      await _prepareLocalStateForUser(userId);

      // handles slow profile trigger creation on first signup
      Map<String, dynamic>? row;
      for (int attempt = 0; attempt < 5; attempt++) {
        row = await _client
            .from('users_public')
            .select('onboarding_complete, username, date_of_birth')
            .eq('id', userId)
            .maybeSingle();

        if (row != null) break;

        if (attempt < 4) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }

// If after 5 retries the row still doesn't exist, the DB trigger failed.
// Create a minimal stub row so the app can proceed to onboarding.
// The full row gets created in completeOnboarding() via upsert.
      if (row == null) {
        AppLogger.warn(
            'auth: trigger row missing after 5 retries, creating stub');
        try {
          await _client.from('users_public').insert({
            'id': userId,
            'username': null,
            'display_name': _client.auth.currentUser?.userMetadata?['full_name']
                    as String? ??
                '',
            'trust_tier': 'unverified',
            'trust_score': 0,
            'echo_count': 0,
            'proof_count': 0,
            'is_public': true,
            'onboarding_complete': false,
          });
          // Re-fetch to confirm the row exists now.
          row = await _client
              .from('users_public')
              .select('onboarding_complete, username, date_of_birth')
              .eq('id', userId)
              .maybeSingle();
        } catch (e) {
          AppLogger.error('auth: stub row creation failed $e');
          // Row creation failed — proceed as new user without a row.
          // Onboarding will create it via upsert.
        }
      }

      if (row == null) {
        _hasUsername = false;
        _hasUsernameChecked = true;
        _needsAgeGender = true;
        _clearCompletedOnboardingFlags();
      } else {
        final done = row['onboarding_complete'] as bool? ?? false;
        final username = row['username'] as String?;
        _hasUsername = done && username != null && username.trim().isNotEmpty;
        _hasUsernameChecked = true;
        _needsAgeGender = row['date_of_birth'] == null;
        if (!_hasUsername) _clearCompletedOnboardingFlags();
      }
    } catch (e) {
      _hasUsername = false;
      _hasUsernameChecked = true;
      AppLogger.error('auth: profile check failed $e');
    }

    _checkingUsername = false;
    notifyListeners(); // Single notify after all retries complete.
  }

  Future<bool> sendOtp({required String email}) async {
    _setLoading(true);
    _error = null;
    try {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
        // The magic link in the email points to this URL.
        // When tapped on Android, the app intercepts it via the intent filter.
        emailRedirectTo: 'echoproof://auth-callback',
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
      await _prepareLocalStateForUser(res.user!.id);
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

      AppLogger.info(
          'auth: Supabase sign in successful, clearing stale state then checking');

// Clear stale Hive onboarding state BEFORE checking username.
// Must run before checkUsername so the router never sees a stale
// onboarding_done=true with hasUsername=false simultaneously.
      final box = Hive.box('app_settings');
      final currentUserId = _client.auth.currentUser?.id;
      final lastUserId = box.get('last_signed_in_user_id') as String?;
      if (lastUserId != currentUserId) {
        AppLogger.info(
            'auth: different user detected, wiping stale onboarding state');
        await box.delete('onboarding_done');
        await box.delete('onboarding_step');
        await box.delete('onboarding_username_set');
      }
      await box.put('last_signed_in_user_id', currentUserId ?? '');

// Now check the DB for username/onboarding status.
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
    DateTime? dateOfBirth,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    try {
      final publicPatch = <String, dynamic>{
        'age': age,
        'gender': gender,
      };
      if (dateOfBirth != null) {
        publicPatch['date_of_birth'] =
            '${dateOfBirth.year.toString().padLeft(4, '0')}-'
            '${dateOfBirth.month.toString().padLeft(2, '0')}-'
            '${dateOfBirth.day.toString().padLeft(2, '0')}';
      }
      final updateRes = await _client
          .from('users_public')
          .update(publicPatch)
          .eq('id', userId)
          .select('id');

      if ((updateRes as List).isEmpty) {
        final fallbackUsername =
            'user${userId.replaceAll('-', '').substring(0, 8)}';
        await _client.from('users_public').upsert(
          {
            'id': userId,
            'username': fallbackUsername,
            'display_name': _displayNameFromCurrentUser() ?? fallbackUsername,
            'onboarding_complete': false,
            'trust_tier': 'unverified',
            'trust_score': 0,
            'echo_count': 0,
            'proof_count': 0,
            'is_public': true,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            ...publicPatch,
          },
          onConflict: 'id',
        );
      }

      _needsAgeGender = false;
      _hasUsernameChecked = true;
      notifyListeners();
    } catch (e) {
      AppLogger.error('auth: save age/gender failed $e');
    }
  }

  Future<void> deleteIncompleteAccount() async {
    try {
      await _google.signOut();
      await _client.auth.signOut();
      _hasUsername = false;
      _hasUsernameChecked = false;
      _googleDisplayName = null;
      _needsAgeGender = false;
      _clearOnboardingState();
      Hive.box(_settingsBox).delete(_lastSignedInUserIdKey);
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
      _needsAgeGender = false;
      _clearOnboardingState();
      Hive.box(_settingsBox).delete(_lastSignedInUserIdKey);
      AppLogger.info('auth: signed out, onboarding state cleared');
      notifyListeners();
    } catch (e) {
      AppLogger.error('auth: sign out failed $e');
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  Future<void> _syncSignedInUser(User? user) async {
    if (user == null) return;
    await _prepareLocalStateForUser(user.id);
    _hasUsernameChecked = false;
    await checkUsername();
  }

  Future<void> _prepareLocalStateForUser(String userId) async {
    final box = Hive.box(_settingsBox);
    final lastUserId = box.get(_lastSignedInUserIdKey) as String?;

    if (lastUserId != userId) {
      AppLogger.info('auth: signed-in user changed, clearing onboarding state');
      _clearOnboardingState();
    }

    await box.put(_lastSignedInUserIdKey, userId);
  }

  void _clearOnboardingState() {
    final box = Hive.box(_settingsBox);
    box.delete(_onboardingDoneKey);
    box.delete(_onboardingStepKey);
    box.delete(_onboardingUsernameSetKey);
  }

  void _clearCompletedOnboardingFlags() {
    final box = Hive.box(_settingsBox);
    box.delete(_onboardingDoneKey);
    box.delete(_onboardingUsernameSetKey);
  }

  String? _displayNameFromCurrentUser() {
    final metadata = currentUser?.userMetadata ?? const <String, dynamic>{};
    final fullName = metadata['full_name'] as String?;
    final name = metadata['name'] as String?;
    return _googleDisplayName ?? fullName ?? name;
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
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
