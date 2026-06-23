// onboarding step 1 identity intro
// explains anonymous but verified model
// uses onboardingservice via provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_story_frame.dart';

class StepIdentity extends StatelessWidget {
  const StepIdentity({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingStoryFrame(
      currentStep: 2,
      totalSteps: 7,
      title: context.l('First, the mask stays yours.'),
      body: context.l(
        'EchoProof verifies privately so public trust can grow without exposing your real identity.',
      ),
      sceneIcon: Icons.shield_outlined,
      sceneLabel: context.l('private identity, public trust signal'),
      footer: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.read<OnboardingService>().nextStep(),
          child: Text(context.l('Got it, continue')),
        ),
      ),
      children: [
        _IdentityStoryPoint(
          icon: Icons.verified_user_outlined,
          title: context.l('Verified in private'),
          body: context.l('Your legal identity never becomes profile text.'),
        ),
        const SizedBox(height: AppSpacing.md),
        _IdentityStoryPoint(
          icon: Icons.person_outline,
          title: context.l('Anonymous in public'),
          body: context.l('People see your handle and trust level, not you.'),
        ),
        const SizedBox(height: AppSpacing.md),
        _IdentityStoryPoint(
          icon: Icons.trending_up_outlined,
          title: context.l('Credibility can grow'),
          body: context.l('Helpful signals and proof build stronger weight.'),
        ),
      ],
    );
  }
}

class _IdentityStoryPoint extends StatelessWidget {
  const _IdentityStoryPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AppColors.fernGreen),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.textTheme.titleSmall?.copyWith(
                      color: AppColors.charcoal,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    body,
                    style: AppTypography.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
