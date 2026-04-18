// onboarding step progress indicator
// animated dots — filled for completed, current, upcoming

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
    return Row(
      children: List.generate(totalSteps, (i) {
        final stepNum = i + 1;
        final isDone    = stepNum < currentStep;
        final isCurrent = stepNum == currentStep;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          margin: const EdgeInsets.only(right: AppSpacing.xs),
          width: isCurrent ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isDone || isCurrent ? AppColors.charcoal : AppColors.borderMedium,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}