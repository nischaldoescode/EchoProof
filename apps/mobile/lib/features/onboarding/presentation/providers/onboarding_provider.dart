// onboarding provider
// manages the 5-step onboarding flow state
// persists completion flag to hive so onboarding never shows again

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/avatar_service.dart';

/// local storage key — stored in hive after onboarding completes
const _kOnboardingComplete = 'onboarding_complete';

/// state for the 5-step onboarding flow
class OnboardingState {
  const OnboardingState({
    this.currentStep = 1,
    this.selectedCategories = const [],
    this.username = '',
    this.isComplete = false,
  });

  final int currentStep;
  final List<String> selectedCategories;
  final String username;
  final bool isComplete;

  OnboardingState copyWith({
    int? currentStep,
    List<String>? selectedCategories,
    String? username,
    bool? isComplete,
  }) {
    return OnboardingState(
      currentStep: currentStep ?? this.currentStep,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      username: username ?? this.username,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

class OnboardingNotifier extends Notifier<OnboardingState> {
  @override
  OnboardingState build() => const OnboardingState();

  /// advances to the next step, clamped at step 5
  void nextStep() {
    if (state.currentStep < 5) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  /// goes back one step
  void previousStep() {
    if (state.currentStep > 1) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  /// toggles a category in/out of selected list
  void toggleCategory(String category) {
    final current = List<String>.from(state.selectedCategories);
    if (current.contains(category)) {
      current.remove(category);
    } else {
      current.add(category);
    }
    state = state.copyWith(selectedCategories: current);
  }

  /// updates the chosen anonymous username
  void setUsername(String username) {
    state = state.copyWith(username: username);
  }

  Future<void> completeOnboarding() async {
    // generate and cache avatar using dicebear — runs once, never again
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null && state.username.isNotEmpty) {
        final avatarService = AvatarService(client);
        await avatarService.generateAndStore(
          userId: userId,
          username: state.username,
        );
      }
    } catch (_) {
      // avatar generation failing must never block onboarding
      // user will get a fallback icon instead
    }

    final box = Hive.box('app_settings');
    await box.put(_kOnboardingComplete, true);
    state = state.copyWith(isComplete: true);
  }
}

final onboardingProvider =
    NotifierProvider<OnboardingNotifier, OnboardingState>(
  OnboardingNotifier.new,
);

/// whether this user has already completed onboarding
final isOnboardingCompleteProvider = Provider<bool>((ref) {
  final box = Hive.box('app_settings');
  return box.get(_kOnboardingComplete, defaultValue: false) as bool;
});
