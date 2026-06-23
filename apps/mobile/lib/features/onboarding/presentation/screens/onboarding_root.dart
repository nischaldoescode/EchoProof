// onboarding_root.dart
// routes between all 7 steps via onboardingservice.currentstep
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
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // step motion is intentionally small and fixed in pixels. using a child
    // size fraction here can jitter if split view or keyboard insets resize
    // the onboarding page while animatedswitcher is still fading old content.
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        return AnimatedBuilder(
          animation: animation,
          child: RepaintBoundary(child: child),
          builder: (context, child) {
            final raw = animation.value.clamp(0.0, 1.0).toDouble();
            final fade = Curves.easeOutCubic.transform(raw);

            if (reduceMotion) {
              return Opacity(opacity: fade, child: child);
            }

            final eased = Curves.easeOutCubic.transform(raw);
            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            final offset = (1 - eased) * 14;
            final snappedOffset =
                (offset * devicePixelRatio).roundToDouble() / devicePixelRatio;

            return Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(snappedOffset, 0),
                child: child,
              ),
            );
          },
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
