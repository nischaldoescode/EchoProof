// onboarding step progress indicator
// animated markers filled for completed and current, grey for upcoming

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';

class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'onboarding progress $currentStep of $totalSteps',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(totalSteps, (i) {
          final stepNum = i + 1;
          final isDone = stepNum < currentStep;
          final isCurrent = stepNum == currentStep;

          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: EdgeInsets.only(
              right: i == totalSteps - 1 ? 0 : AppSpacing.xs,
            ),
            width: isCurrent ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: isDone || isCurrent
                  ? AppColors.charcoal
                  : AppColors.borderMedium,
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }
}
