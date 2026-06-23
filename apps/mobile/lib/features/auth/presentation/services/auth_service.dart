// auth service
// @params none

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/device_service.dart';
import '../../../../core/utils/logger.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../../core/services/avatar_service.dart';
import '../../../../core/services/app_analytics_service.dart';

class AuthService extends ChangeNotifier {
  static const _settingsBox = 'app_settings';
  static const _onboardingDoneKey = 'onboarding_done';
  static const _onboardingStepKey = 'onboarding_step';
  static const _onboardingUsernameSetKey = 'onboarding_username_set';
  static const _lastSignedInUserIdKey = 'last_signed_in_user_id';
  static const _otpRequestPrefix = 'otp_requested_at:';
  static const _otpRequestCooldown = Duration(seconds: 90);
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
  bool _hasPendingAccountDeletion = false;
  DateTime? _accountDeletionRestoreUntil;
  String? _accountDeletionReason;

  bool get isLoading => _isLoading;
  String? get error => _error;
  User? get currentUser => _client.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  bool get hasUsername => _hasUsername;
  bool get hasPendingAccountDeletion => _hasPendingAccountDeletion;
  DateTime? get accountDeletionRestoreUntil => _accountDeletionRestoreUntil;
  String? get accountDeletionReason => _accountDeletionReason;

  /// true after at least one successful db check has completed
  /// the router uses this to avoid redundant network calls on every
  /// navigation event
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
        _clearPendingDeletionState();
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

  Future<void>? _usernameCheckFuture;

  Future<void> checkUsername() {
    final running = _usernameCheckFuture;
    if (running != null) return running;

    final future = _checkUsernameInternal();
    _usernameCheckFuture = future;
    return future.whenComplete(() => _usernameCheckFuture = null);
  }

  Future<void> _checkUsernameInternal() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        _hasUsername = false;
        _hasUsernameChecked = true;
        _needsAgeGender = false;
        notifyListeners();
        return;
      }

      await _prepareLocalStateForUser(userId);

      final accountStatus = await _loadCurrentAccountStatus();
      if (accountStatus.isDeletedOrExpired) {
        AppLogger.warn('auth: signed-in account is no longer active');
        await signOut(enforceCooldown: false);
        return;
      }
      _applyAccountStatus(accountStatus);

      // handles slow profile trigger creation on first signup
      Map<String, dynamic>? row;
      for (int attempt = 0; attempt < 5; attempt++) {
        row = await _client
            .from('users_public')
            .select(
              'onboarding_complete, username, date_of_birth, deletion_requested_at, deletion_grace_ends_at, deletion_cancelled_at, deletion_reason',
            )
            .eq('id', userId)
            .maybeSingle();

        if (row != null) break;

        if (attempt < 4) {
          await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }

      // if after 5 retries the row still doesn't exist, the db trigger failed
      // create a minimal stub row so the app can proceed to onboarding
      // the full row gets created in completeonboarding() via upsert
      if (row == null) {
        if (!accountStatus.isProfilePending) {
          AppLogger.warn('auth: profile row missing for established account');
          await signOut(enforceCooldown: false);
          return;
        }

        AppLogger.warn(
          'auth: trigger row missing after 5 retries, creating stub',
        );
        try {
          await _client.from('users_public').insert({
            'id': userId,
            'username': null,
            'display_name':
                _client.auth.currentUser?.userMetadata?['full_name']
                    as String? ??
                '',
            'avatar_url': AvatarService.defaultAvatarUrlFor(userId),
            'trust_tier': 'unverified',
            'trust_score': 0,
            'echo_count': 0,
            'proof_count': 0,
            'is_public': true,
            'onboarding_complete': false,
          });
          // re-fetch to confirm the row exists now
          row = await _client
              .from('users_public')
              .select(
                'onboarding_complete, username, date_of_birth, deletion_requested_at, deletion_grace_ends_at, deletion_cancelled_at, deletion_reason',
              )
              .eq('id', userId)
              .maybeSingle();
        } catch (e) {
          AppLogger.error('auth: stub row creation failed $e');
          // row creation failed proceed as new user without a row
          // onboarding will create it via upsert
        }
      }

      if (row == null) {
        _hasUsername = false;
        _hasUsernameChecked = true;
        _needsAgeGender = true;
        _clearCompletedOnboardingFlags();
      } else {
        _applyProfileDeletionState(row);
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

    notifyListeners(); // single notify after all retries complete
  }

  Future<bool> sendOtp({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final localCooldown = otpCooldownRemaining(normalizedEmail);
    if (localCooldown > 0) {
      _error =
          'Please wait ${_formatCooldown(localCooldown)} before requesting another code.';
      notifyListeners();
      return false;
    }

    _setLoading(true);
    _error = null;
    try {
      final emailValidation = await _validateAllowedEmail(normalizedEmail);
      if (!emailValidation.allowed) {
        _error = emailValidation.message;
        _setLoading(false);
        return false;
      }

      final authCooldown = await _consumeActionCooldown(
        action: 'auth_login',
        subject: 'ip-only',
        windowSeconds: 30 * 60,
        maxActions: 3,
        includeIp: true,
      );
      if (authCooldown > 0) {
        _error =
            'Too many sign-in requests from this network. Try again in ${_formatCooldown(authCooldown)}.';
        _setLoading(false);
        return false;
      }

      final accountCooldown = await _consumeActionCooldown(
        action: 'auth_login',
        subject: normalizedEmail,
        windowSeconds: 30 * 60,
        maxActions: 3,
        includeIp: true,
      );
      if (accountCooldown > 0) {
        _error =
            'Too many sign-in requests. Try again in ${_formatCooldown(accountCooldown)}.';
        _setLoading(false);
        return false;
      }

      await _client.auth.signInWithOtp(
        email: normalizedEmail,
        shouldCreateUser: true,
        // if the email template includes a link, it should come back to the
        // app. the 6-digit code still works independently of the link
        emailRedirectTo: _authRedirectUrl,
      );
      await _markOtpRequested(normalizedEmail);
      unawaited(
        AppAnalyticsService.instance.logEvent(
          'auth_otp_requested',
          parameters: const {'method': 'email'},
        ),
      );
      AppLogger.info('auth: OTP sent to $normalizedEmail');
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

  Future<bool> verifyOtp({required String email, required String otp}) async {
    _setLoading(true);
    _error = null;
    try {
      final res = await _verifyEmailOtpWithSignupFallback(
        email: email,
        otp: otp,
      );
      if (res.user == null) {
        _error = 'Verification failed. Try again.';
        _setLoading(false);
        return false;
      }
      AppLogger.info('auth: OTP verified ${res.user!.id}');
      await _prepareLocalStateForUser(res.user!.id);
      await checkUsername();
      unawaited(AppAnalyticsService.instance.logLogin(method: 'email_otp'));
      _setLoading(false);
      return true;
    } on AuthException catch (e) {
      _error = _friendly(e.message);
      _setLoading(false);
      return false;
    }
  }

  Future<bool> resendOtp({required String email}) => sendOtp(email: email);

  Future<AuthResponse> _verifyEmailOtpWithSignupFallback({
    required String email,
    required String otp,
  }) async {
    try {
      return await _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.email,
      );
    } on AuthException catch (e) {
      final message = e.message.toLowerCase();
      final canRetryAsSignup =
          message.contains('token') ||
          message.contains('otp') ||
          message.contains('invalid') ||
          message.contains('expired');

      if (!canRetryAsSignup) rethrow;

      return _client.auth.verifyOTP(
        email: email,
        token: otp,
        type: OtpType.signup,
      );
    }
  }

  Future<bool> handleAuthCallback(Uri uri) async {
    _setLoading(true);
    _error = null;
    try {
      final tokenHash = uri.queryParameters['token_hash'];

      if (tokenHash != null && tokenHash.isNotEmpty) {
        await _client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: _otpTypeFromRedirect(uri.queryParameters['type']),
        );
      } else if (_hasAuthPayload(uri)) {
        await _client.auth.getSessionFromUrl(uri);
      }

      final user = _client.auth.currentUser;
      if (user == null) {
        _error = 'Sign-in link could not be completed. Enter the code instead.';
        _setLoading(false);
        return false;
      }

      await _prepareLocalStateForUser(user.id);
      await checkUsername();
      unawaited(AppAnalyticsService.instance.logLogin(method: 'email_link'));
      _setLoading(false);
      return true;
    } on AuthException catch (e) {
      AppLogger.error('auth: callback failed ${e.message}');
      _error = _friendly(e.message);
      _setLoading(false);
      return false;
    } catch (e) {
      AppLogger.error('auth: callback failed $e');
      _error = 'Sign-in link could not be completed. Enter the code instead.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _error = null;
    try {
      final authCooldown = await _consumeActionCooldown(
        action: 'auth_login',
        subject: 'ip-only',
        windowSeconds: 30 * 60,
        maxActions: 3,
        includeIp: true,
      );
      if (authCooldown > 0) {
        _error =
            'Too many sign-in requests from this network. Try again in ${_formatCooldown(authCooldown)}.';
        _setLoading(false);
        return false;
      }

      final googleCooldown = await _consumeActionCooldown(
        action: 'auth_login',
        subject: 'google_oauth',
        windowSeconds: 30 * 60,
        maxActions: 3,
        includeIp: true,
      );
      if (googleCooldown > 0) {
        _error =
            'Too many sign-in requests. Try again in ${_formatCooldown(googleCooldown)}.';
        _setLoading(false);
        return false;
      }

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
          'auth: Google idToken is null — serverClientId may be wrong',
        );
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
        'auth: Supabase sign in successful, clearing stale state then checking',
      );
      unawaited(AppAnalyticsService.instance.logLogin(method: 'google'));

      // clear stale hive onboarding state before checking username
      // must run before checkusername so the router never sees a stale
      // onboarding_done=true with hasusername=false simultaneously
      final box = Hive.box('app_settings');
      final currentUserId = _client.auth.currentUser?.id;
      final lastUserId = box.get('last_signed_in_user_id') as String?;
      if (lastUserId != currentUserId) {
        AppLogger.info(
          'auth: different user detected, wiping stale onboarding state',
        );
        await box.delete('onboarding_done');
        await box.delete('onboarding_step');
        await box.delete('onboarding_username_set');
      }
      await box.put('last_signed_in_user_id', currentUserId ?? '');

      // now check the db for username/onboarding status
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
        'auth: AuthException during Google sign in: ${e.message}',
      );
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
      final publicPatch = <String, dynamic>{'age': age, 'gender': gender};
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
        await _client.from('users_public').upsert({
          'id': userId,
          'username': fallbackUsername,
          'display_name': _displayNameFromCurrentUser() ?? fallbackUsername,
          'avatar_url': AvatarService.defaultAvatarUrlFor(userId),
          'onboarding_complete': false,
          'trust_tier': 'unverified',
          'trust_score': 0,
          'echo_count': 0,
          'proof_count': 0,
          'is_public': true,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          ...publicPatch,
        }, onConflict: 'id');
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
      await _markCurrentDeviceSignedOut();
      await _google.signOut();
      await _client.auth.signOut();
      _hasUsername = false;
      _hasUsernameChecked = false;
      _googleDisplayName = null;
      _needsAgeGender = false;
      _clearPendingDeletionState();
      _clearOnboardingState();
      Hive.box(_settingsBox).delete(_lastSignedInUserIdKey);
      notifyListeners();
    } catch (e) {
      AppLogger.error('auth: sign out failed $e');
    }
  }

  Future<bool> signOut({bool enforceCooldown = true}) async {
    try {
      if (enforceCooldown) {
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          final authCooldown = await _consumeActionCooldown(
            action: 'auth_logout',
            subject: 'ip-only',
            windowSeconds: 30 * 60,
            maxActions: 3,
            includeIp: true,
          );
          if (authCooldown > 0) {
            _error =
                'Too many sign-out attempts from this network. Try again in ${_formatCooldown(authCooldown)}.';
            notifyListeners();
            return false;
          }

          final userCooldown = await _consumeActionCooldown(
            action: 'auth_logout',
            subject: userId,
            windowSeconds: 30 * 60,
            maxActions: 3,
            includeIp: true,
          );
          if (userCooldown > 0) {
            _error =
                'Too many sign-out attempts. Try again in ${_formatCooldown(userCooldown)}.';
            notifyListeners();
            return false;
          }
        }
      }

      unawaited(AppAnalyticsService.instance.logEvent('logout'));
      await _markCurrentDeviceSignedOut();
      await _google.signOut();
      await _client.auth.signOut();
      _hasUsername = false;
      _hasUsernameChecked = false;
      _googleDisplayName = null;
      _needsAgeGender = false;
      _clearPendingDeletionState();
      _clearOnboardingState();
      Hive.box(_settingsBox).delete(_lastSignedInUserIdKey);
      AppLogger.info('auth: signed out, onboarding state cleared');
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('auth: sign out failed $e');
      _error = 'Could not sign out. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<void> _markCurrentDeviceSignedOut() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final deviceId = await DeviceService(
        const FlutterSecureStorage(),
      ).getDeviceId();
      final now = DateTime.now().toUtc().toIso8601String();
      await _client
          .from('account_devices')
          .update({
            'active': false,
            'replaced_at': now,
            'updated_at': now,
            'last_seen_at': now,
          })
          .eq('user_id', userId)
          .eq('device_id', deviceId);
    } catch (e) {
      AppLogger.warn('auth: could not mark account device signed out $e');
    }
  }

  int otpCooldownRemaining(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return 0;
    final box = Hive.box(_settingsBox);
    final lastIso = box.get('$_otpRequestPrefix$normalizedEmail') as String?;
    final last = lastIso == null ? null : DateTime.tryParse(lastIso);
    if (last == null) return 0;
    final elapsed = DateTime.now().difference(last);
    final remaining = _otpRequestCooldown - elapsed;
    return remaining.isNegative ? 0 : remaining.inSeconds + 1;
  }

  Future<void> _markOtpRequested(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    await Hive.box(_settingsBox).put(
      '$_otpRequestPrefix$normalizedEmail',
      DateTime.now().toIso8601String(),
    );
  }

  Future<int> _consumeActionCooldown({
    required String action,
    required String subject,
    required int windowSeconds,
    required int maxActions,
    required bool includeIp,
  }) async {
    try {
      final response = await _client.rpc(
        'consume_action_cooldown',
        params: {
          'p_action': action,
          'p_subject': subject,
          'p_window_seconds': windowSeconds,
          'p_max_actions': maxActions,
          'p_include_ip': includeIp,
        },
      );
      final map = Map<String, dynamic>.from(response as Map);
      return (map['retry_after_seconds'] as num?)?.toInt() ?? 0;
    } catch (e) {
      AppLogger.warn('auth: cooldown check failed $e');
      return 0;
    }
  }

  Future<bool> restorePendingAccountDeletion() async {
    _setLoading(true);
    _error = null;
    try {
      await _client.rpc('restore_own_deleted_account');
      _clearPendingDeletionState();
      _hasUsernameChecked = false;
      await checkUsername();
      _setLoading(false);
      return true;
    } catch (e) {
      AppLogger.error('auth: account recovery failed $e');
      _error = 'Could not restore this account. Please try again.';
      _setLoading(false);
      return false;
    }
  }

  Future<_AccountStatusResult> _loadCurrentAccountStatus() async {
    try {
      final response = await _client.rpc('current_account_status');
      return _AccountStatusResult.fromMap(
        Map<String, dynamic>.from(response as Map),
      );
    } catch (e) {
      AppLogger.warn('auth: account status check failed $e');
      return const _AccountStatusResult(status: 'unknown');
    }
  }

  void _applyAccountStatus(_AccountStatusResult status) {
    if (status.status == 'pending_deletion') {
      _hasPendingAccountDeletion = true;
      _accountDeletionRestoreUntil = status.restoreUntil;
      _accountDeletionReason = status.reason;
      return;
    }

    if (status.status == 'active' || status.status == 'profile_pending') {
      _clearPendingDeletionState();
    }
  }

  void _applyProfileDeletionState(Map<String, dynamic> row) {
    final requestedAt = DateTime.tryParse(
      row['deletion_requested_at'] as String? ?? '',
    );
    final cancelledAt = DateTime.tryParse(
      row['deletion_cancelled_at'] as String? ?? '',
    );
    final restoreUntil = DateTime.tryParse(
      row['deletion_grace_ends_at'] as String? ?? '',
    );

    if (requestedAt != null &&
        cancelledAt == null &&
        restoreUntil != null &&
        restoreUntil.isAfter(DateTime.now().toUtc())) {
      _hasPendingAccountDeletion = true;
      _accountDeletionRestoreUntil = restoreUntil;
      _accountDeletionReason = row['deletion_reason'] as String?;
    } else {
      _clearPendingDeletionState();
    }
  }

  void _clearPendingDeletionState() {
    _hasPendingAccountDeletion = false;
    _accountDeletionRestoreUntil = null;
    _accountDeletionReason = null;
  }

  Future<_EmailValidationResult> _validateAllowedEmail(String email) async {
    try {
      final response = await _client.rpc(
        'validate_auth_email',
        params: {'p_email': email},
      );
      final map = Map<String, dynamic>.from(response as Map);
      final allowed = map['allowed'] as bool? ?? false;
      final reason = map['reason'] as String? ?? 'invalid';

      if (allowed) return const _EmailValidationResult.allowed();

      return _EmailValidationResult.blocked(switch (reason) {
        'unsupported_domain' =>
          'Use a trusted email provider like Gmail, Outlook, Hotmail, Yahoo, iCloud, or Proton.',
        'invalid_format' => 'Enter a valid email address.',
        'account_deletion_pending' =>
          'This email is inside a 7-day deletion window. Sign back in with the original account to restore it, or try again after the window ends.',
        _ => 'This email address is not supported.',
      });
    } catch (e) {
      AppLogger.warn('auth: email validation failed $e');
      return const _EmailValidationResult.blocked(
        'Email validation is unavailable. Please try again soon.',
      );
    }
  }

  String _formatCooldown(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes <= 1) return '$seconds seconds';
    return '$minutes minutes';
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
    if (m.contains('otp') && m.contains('invalid')) {
      return 'Incorrect code. Try again.';
    }
    if (m.contains('rate limit') ||
        m.contains('too many') ||
        m.contains('over_email_send_rate_limit')) {
      return 'Please wait a minute before requesting another code.';
    }
    if (m.contains('code verifier')) {
      return 'This sign-in link can only be opened on the device that requested it. Enter the code instead.';
    }
    if (m.contains('one-time token') ||
        (m.contains('email link') && m.contains('invalid'))) {
      return 'This sign-in link has expired. Request a new code.';
    }
    if (m.contains('expired')) {
      return 'Code expired. Request a new one.';
    }
    if (m.contains('invalid_credentials')) {
      return 'Incorrect email or password.';
    }
    if (m.contains('user_already_exists')) {
      return 'Account already exists. Sign in instead.';
    }
    if (m.contains('email_not_confirmed')) {
      return 'Please verify your email first.';
    }
    if (m.contains('too_many_requests')) {
      return 'Too many attempts. Wait a moment.';
    }
    if (m.contains('network')) {
      return 'Network error. Check your connection.';
    }
    return message;
  }

  bool _hasAuthPayload(Uri uri) {
    return uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error_description') ||
        uri.fragment.contains('access_token') ||
        uri.fragment.contains('error_description');
  }

  OtpType _otpTypeFromRedirect(String? type) {
    switch (type) {
      case 'signup':
        return OtpType.signup;
      case 'invite':
        return OtpType.invite;
      case 'magiclink':
        return OtpType.magiclink;
      case 'recovery':
        return OtpType.recovery;
      case 'email_change':
        return OtpType.emailChange;
      case 'email':
      default:
        return OtpType.email;
    }
  }
}

class _EmailValidationResult {
  const _EmailValidationResult._(this.allowed, this.message);
  const _EmailValidationResult.allowed() : this._(true, null);
  const _EmailValidationResult.blocked(String message) : this._(false, message);

  final bool allowed;
  final String? message;
}

class _AccountStatusResult {
  const _AccountStatusResult({
    required this.status,
    this.restoreUntil,
    this.reason,
  });

  final String status;
  final DateTime? restoreUntil;
  final String? reason;

  bool get isDeletedOrExpired =>
      status == 'deleted' || status == 'expired_deletion';
  bool get isProfilePending => status == 'profile_pending';

  factory _AccountStatusResult.fromMap(Map<String, dynamic> map) {
    return _AccountStatusResult(
      status: map['status'] as String? ?? 'unknown',
      restoreUntil: DateTime.tryParse(map['restore_until'] as String? ?? ''),
      reason: map['reason'] as String?,
    );
  }
}
