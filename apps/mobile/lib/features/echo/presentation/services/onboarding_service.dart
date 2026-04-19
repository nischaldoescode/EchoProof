// onboarding service
// manages the 5-step onboarding flow state
// replaces onboarding_provider.dart (riverpod version)

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/avatar_service.dart';
import '../../../../core/utils/logger.dart';

const _kOnboardingComplete = 'onboarding_complete';

class OnboardingService extends ChangeNotifier {
  int _currentStep = 1;
  int get currentStep => _currentStep;

  final List<String> _selectedCategories = [];
  List<String> get selectedCategories => List.unmodifiable(_selectedCategories);

  String _username = '';
  String get username => _username;

  bool _isSubmitting = false;
  bool get isSubmitting => _isSubmitting;

  // checks hive to see if onboarding was previously completed
  // called synchronously — hive box must already be open
  bool isComplete() {
    final box = Hive.box('app_settings');
    return box.get(_kOnboardingComplete, defaultValue: false) as bool;
  }

  void nextStep() {
    if (_currentStep < 5) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 1) {
      _currentStep--;
      notifyListeners();
    }
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

  // completes onboarding: generates avatar, saves completion flag to hive
  Future<void> completeOnboarding() async {
    _isSubmitting = true;
    notifyListeners();

    // generate dicebear avatar — fire and forget, never blocks onboarding
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null && _username.isNotEmpty) {
        final avatarService = AvatarService(client);
        await avatarService.generateAndStore(
          userId: userId,
          username: _username,
        );
      }
    } catch (e) {
      AppLogger.warn(
          'onboarding: avatar generation failed — continuing anyway');
    }

    final box = Hive.box('app_settings');
    await box.put(_kOnboardingComplete, true);

    _isSubmitting = false;
    notifyListeners();
  }
}
