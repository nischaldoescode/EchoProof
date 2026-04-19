// onboarding root
// manages animated transitions between the 5 onboarding steps
// uses OnboardingService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/onboarding_service.dart';
import 'step_identity.dart';
import 'step_categories.dart';
import 'step_username.dart';
import 'step_trust_intro.dart';
import 'step_first_echo.dart';

class OnboardingRoot extends StatelessWidget {
  const OnboardingRoot({super.key});

  static const _steps = [
    StepIdentity(),
    StepCategories(),
    StepUsername(),
    StepTrustIntro(),
    StepFirstEcho(),
  ];

  @override
  Widget build(BuildContext context) {
    final service = context.watch<OnboardingService>();

    if (service.isComplete()) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.go('/feed'),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, animation) {
        final slideIn = Tween<Offset>(
          begin: const Offset(1, 0),
          end:   Offset.zero,
        ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: const Interval(0, 0.5),
          ),
        );
        return FadeTransition(
          opacity: fadeIn,
          child: SlideTransition(position: slideIn, child: child),
        );
      },
      child: KeyedSubtree(
        key:   ValueKey(service.currentStep),
        child: _steps[(service.currentStep - 1).clamp(0, 4)],
      ),
    );
  }
}