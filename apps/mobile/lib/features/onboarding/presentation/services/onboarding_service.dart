// onboarding service
// manages the 5-step onboarding flow state
// replaces onboarding_provider.dart (riverpod version)

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/avatar_service.dart';
import '../../../../core/utils/logger.dart';

// single source of truth for all hive keys
const _kStep = 'onboarding_step';
const _kUsernameSet = 'onboarding_username_set';
const _kDone = 'onboarding_done';

class OnboardingService extends ChangeNotifier {
  final List<String> _selectedCategories = [];
  List<String> get selectedCategories => List.unmodifiable(_selectedCategories);

  String _username = '';
  String get username => _username;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  // ALL step reads go through Hive — no private int field
  int get currentStep {
    return Hive.box('app_settings').get(_kStep, defaultValue: 1) as int;
  }

  bool isComplete() {
    return Hive.box('app_settings').get(_kDone, defaultValue: false) as bool;
  }

  bool get hasSetUsername {
    return Hive.box('app_settings').get(_kUsernameSet, defaultValue: false)
        as bool;
  }

  void setStep(int step) {
    AppLogger.info('onboarding: setStep $step');
    Hive.box('app_settings').put(_kStep, step);
    notifyListeners();
  }

  void nextStep() {
    final current = currentStep; // reads from Hive
    AppLogger.info('onboarding: nextStep called, current=$current');
    if (current < 5) {
      setStep(current + 1); // writes to Hive, notifies
    } else {
      complete();
    }
  }

  void previousStep() {
    final current = currentStep;
    if (current > 1) {
      setStep(current - 1);
    }
  }

  void advance() {
    nextStep(); // advance and nextStep are now equivalent
  }

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

  Future<void> completeOnboarding() async {
    _isSubmitting = true;
    notifyListeners();

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        final avatarService = AvatarService(client);
        await avatarService.generateAndStore(
          userId: userId,
          username: username.isNotEmpty ? username : userId.substring(0, 8),
        );

        // mark onboarding complete in db so the auth check works on next login
        await client.from('users_public').upsert({
          'id': userId,
          'onboarding_complete': true,
          'username': username.isNotEmpty ? username : null,
          'trust_tier': 'unverified',
          'trust_score': 0,
          'echo_count': 0,
          'proof_count': 0,
          'is_public': true,
          'created_at': DateTime.now().toIso8601String(),
        }, onConflict: 'id');
      }
    } catch (e) {
      AppLogger.warn('onboarding: avatar generation failed, continuing: $e');
    }

    complete();

    _isSubmitting = false;
    notifyListeners();
  }
}
