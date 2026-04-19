// onboarding step 1 — identity intro
// explains anonymous but verified model
// uses OnboardingService via provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_progress.dart';

class StepIdentity extends StatelessWidget {
  const StepIdentity({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const OnboardingProgress(currentStep: 1, totalSteps: 5),
              const SizedBox(height: AppSpacing.xxxl),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.fernGreenLight,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 40,
                    color: AppColors.fernGreen,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'You stay anonymous.',
                style: AppTypography.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'We verify your identity privately. Your real name never appears publicly — only your trust level does.',
                style: AppTypography.textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              ...const [
                (
                  'Your identity is verified privately',
                  Icons.verified_user_outlined
                ),
                ('Your public profile stays anonymous', Icons.person_outline),
                (
                  'Your trust level grows with your activity',
                  Icons.trending_up_outlined
                ),
              ].map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Row(
                      children: [
                        Icon(item.$2, size: 20, color: AppColors.fernGreen),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            item.$1,
                            style: AppTypography.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  )),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.read<OnboardingService>().nextStep(),
                  child: const Text('Got it, continue'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}
