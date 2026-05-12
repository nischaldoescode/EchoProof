// onboarding step 1 — identity intro
// explains anonymous but verified model
// uses OnboardingService via provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_progress.dart';

class StepIdentity extends StatelessWidget {
  const StepIdentity({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final minHeight = constraints.maxHeight;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
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
                      context.l('You stay anonymous.'),
                      style: AppTypography.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l(
                        'We verify your identity privately. Your real name never appears publicly — only your trust level does.',
                      ),
                      style: AppTypography.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    ...[
                      (
                        context.l('Your identity is verified privately'),
                        Icons.verified_user_outlined
                      ),
                      (
                        context.l('Your public profile stays anonymous'),
                        Icons.person_outline
                      ),
                      (
                        context.l('Your trust level grows with your activity'),
                        Icons.trending_up_outlined
                      ),
                    ].map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Row(
                            children: [
                              Icon(item.$2,
                                  size: 20, color: AppColors.fernGreen),
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
                    const SizedBox(height: AppSpacing.xxxl),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            context.read<OnboardingService>().nextStep(),
                        child: Text(context.l('Got it, continue')),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
