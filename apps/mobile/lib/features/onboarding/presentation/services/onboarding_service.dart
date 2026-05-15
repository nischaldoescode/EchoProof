// onboarding service
// manages the multi-step onboarding flow state
// steps: 0=language, 1=identity, 2=categories, 3=username, 4=trust, 5=guide, 6=first_echo

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/avatar_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../auth/presentation/services/auth_service.dart';
import '../../../../core/utils/sanitizer.dart';

const _kStep = 'onboarding_step';
const _kUsernameSet = 'onboarding_username_set';
const _kDone = 'onboarding_done';
const _kLanguage = 'app_language';

class OnboardingService extends ChangeNotifier {
  final List<String> _selectedCategories = [];
  List<String> get selectedCategories => List.unmodifiable(_selectedCategories);

  String _username = '';
  String get username => _username;
  String _displayName = '';
  String get displayName => _displayName;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  // step (Hive-backed)
  int get currentStep =>
      Hive.box('app_settings').get(_kStep, defaultValue: 0) as int;

  bool isComplete() =>
      Hive.box('app_settings').get(_kDone, defaultValue: false) as bool;

  bool get hasSetUsername =>
      Hive.box('app_settings').get(_kUsernameSet, defaultValue: false) as bool;

  String get language =>
      Hive.box('app_settings').get(_kLanguage, defaultValue: 'en') as String;

  // setters
  void setStep(int step) {
    AppLogger.info('onboarding: setStep $step');
    Hive.box('app_settings').put(_kStep, step);
    notifyListeners();
  }

  void setDisplayName(String value) {
    _displayName = value;
    notifyListeners();
  }

  /// Persist selected language code (e.g. 'en', 'hi').
  /// Called from StepLanguage and SettingsScreen.
  void setLanguage(String code) {
    AppLogger.info('onboarding: language set to $code');
    Hive.box('app_settings').put(_kLanguage, code);
    notifyListeners();
  }

  void nextStep() {
    final current = currentStep;
    AppLogger.info('onboarding: nextStep called, current=$current');
    if (current < 6) {
      setStep(current + 1);
    } else {
      complete();
    }
  }

  void previousStep() {
    final current = currentStep;
    if (current > 0) setStep(current - 1);
  }

  // kept for backward-compat with StepUsername
  void advance() => nextStep();

  void markUsernameSet() {
    AppLogger.info('onboarding: markUsernameSet');
    Hive.box('app_settings').put(_kUsernameSet, true);
    notifyListeners();
  }

  void complete() {
    AppLogger.info('onboarding: complete called');
    final box = Hive.box('app_settings');
    box.put(_kDone, true);
    box.put(_kUsernameSet, true);
    notifyListeners();
  }

  void reset() {
    AppLogger.info('onboarding: reset called');
    final box = Hive.box('app_settings');
    box.delete(_kStep);
    box.delete(_kDone);
    box.delete(_kUsernameSet);
    // intentionally keep language so user does not re-pick on re-install
    notifyListeners();
  }

  void toggleCategory(String category) {
    if (_selectedCategories.contains(category)) {
      _selectedCategories.remove(category);
    } else {
      _selectedCategories.add(category);
    }
    notifyListeners();
  }

  void setUsername(String value) {
    _username = value;
    notifyListeners();
  }

  // completeOnboarding
  /// Called from StepFirstEcho (skip or post).
  /// Writes onboarding_complete=true to DB with upsert so it works even if
  /// the trigger-created row is missing (e.g. trigger was broken during dev).
  Future<void> completeOnboarding({AuthService? authService}) async {
    _isSubmitting = true;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;

      if (userId != null) {
        // Generate avatar first — uses maybeSingle so it is safe for new users.
        try {
          final avatarService = AvatarService(client);
          await avatarService.generateAndStore(
            userId: userId,
            username: username.isNotEmpty ? username : userId.substring(0, 8),
          );
        } catch (e) {
          AppLogger.warn(
              'onboarding: avatar generation failed, continuing: $e');
        }

        // Only UPDATE — the DB trigger at signup already created the row.
        // Upsert (INSERT on conflict) fails with RLS 42501 because the
        // authenticated role has no INSERT policy on users_public.
        // We only patch the fields that belong to onboarding completion.
        final patch = <String, dynamic>{
          'onboarding_complete': true,
        };
        if (username.isNotEmpty) {
          patch['username'] = Sanitizer.username(username);
        }

        // Try update first (existing row from trigger).
        // If no row exists yet (trigger delayed or failed), fall back to insert.
        // The insert RLS policy from migration 023 allows this.
        final updateRes = await client
            .from('users_public')
            .update(patch)
            .eq('id', userId)
            .select('id');

        if ((updateRes as List).isEmpty) {
          AppLogger.warn('onboarding: no row to update, attempting upsert');
          // Use upsert (INSERT ... ON CONFLICT DO UPDATE) so that if the avatar
          // service already created a partial row, we merge instead of failing.
          final tempUsername = username.isNotEmpty
              ? username
              : 'user${userId.replaceAll('-', '').substring(0, 8)}';
          await client.from('users_public').upsert(
            {
              'id': userId,
              'username': tempUsername,
              'display_name':
                  displayName.isNotEmpty ? displayName : tempUsername,
              'avatar_url': AvatarService.defaultAvatarUrlFor(userId),
              'onboarding_complete': true,
              'trust_tier': 'unverified',
              'trust_score': 0,
              'echo_count': 0,
              'proof_count': 0,
              'is_public': true,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'id',
          );
        } else {
          // Row existed — patch display_name too if provided.
          if (displayName.isNotEmpty) {
            await client
                .from('users_public')
                .update({'display_name': displayName}).eq('id', userId);
          }
        }

        AppLogger.info('onboarding: onboarding_complete written to DB');
      }
    } catch (e) {
      AppLogger.error('onboarding: completeOnboarding DB write failed: $e');
    }

    complete();
    authService?.markOnboardingComplete();
    _isSubmitting = false;
    notifyListeners();
  }
}
