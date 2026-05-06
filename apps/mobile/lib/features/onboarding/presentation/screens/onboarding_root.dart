// onboarding_root.dart
// routes between all 7 steps via OnboardingService.currentStep
// step 0 = language, 1 = identity, 2 = categories, 3 = username,
// 4 = trust_intro, 5 = guide, 6 = first_echo

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/onboarding_service.dart';
import 'step_language.dart';
import 'step_identity.dart';
import 'step_categories.dart';
import 'step_username.dart';
import 'step_trust_intro.dart';
import 'step_guide.dart';
import 'step_first_echo.dart';

class OnboardingRoot extends StatelessWidget {
  const OnboardingRoot({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<OnboardingService>().currentStep;

    // animated page transitions between steps
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        final fade = Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.6, curve: Curves.easeOut),
          ),
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(step),
        child: switch (step) {
          0 => const StepLanguage(),
          1 => const StepIdentity(),
          2 => const StepCategories(),
          3 => const StepUsername(),
          4 => const StepTrustIntro(),
          5 => const StepGuide(),
          _ => const StepFirstEcho(),
        },
      ),
    );
  }
}
