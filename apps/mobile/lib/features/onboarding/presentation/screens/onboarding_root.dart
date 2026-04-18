// onboarding root — manages animated transitions between the 5 steps
// uses a page-view-like feel with custom 3d slide transitions
// back gesture supported

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/colors.dart';
import '../providers/onboarding_provider.dart';
import 'step_identity.dart';
import 'step_categories.dart';
import 'step_username.dart';
import 'step_trust_intro.dart';
import 'step_first_echo.dart';

class OnboardingRoot extends ConsumerWidget {
  const OnboardingRoot({super.key});

  static const _steps = [
    StepIdentity(),
    StepCategories(),
    StepUsername(),
    StepTrustIntro(),
    StepFirstEcho(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingProvider);

    // when complete, router redirect handles navigation
    if (state.isComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/feed'));
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, animation) {
        // 3d slide transition: new step slides in from right with perspective
        final slideIn = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

        final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
        );

        return FadeTransition(
          opacity: fadeIn,
          child: SlideTransition(position: slideIn, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(state.currentStep),
        child: _steps[(state.currentStep - 1).clamp(0, 4)],
      ),
    );
  }
}