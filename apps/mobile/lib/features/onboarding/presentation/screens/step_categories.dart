// onboarding step 2 category selection
// minimum 3 required
// uses onboardingservice via provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/category_chip.dart';
import '../widgets/onboarding_story_frame.dart';

class StepCategories extends StatelessWidget {
  const StepCategories({super.key});

  static const int _minRequired = 3;

  static const _categories = [
    (label: 'Tech', value: 'tech'),
    (label: 'Finance', value: 'finance'),
    (label: 'Startups', value: 'startups'),
    (label: 'Social Issues', value: 'social_issues'),
    (label: 'Web3', value: 'web3'),
    (label: 'AI', value: 'ai'),
    (label: 'Gaming', value: 'gaming'),
    (label: 'Education', value: 'education'),
    (label: 'Other', value: 'other'),
  ];

  @override
  Widget build(BuildContext context) {
    final service = context.watch<OnboardingService>();
    final selected = service.selectedCategories;
    final canContinue = selected.length >= _minRequired;

    return OnboardingStoryFrame(
      currentStep: 3,
      totalSteps: 7,
      title: context.l('Then choose your signal lanes.'),
      body: context.l(
        'Pick at least {count} areas. Your feed will start with the communities you want to hear from first.',
        {'count': _minRequired},
      ),
      sceneIcon: Icons.tune_rounded,
      sceneLabel: context.l('your feed begins with the topics you choose'),
      sceneBackground: AppColors.sunsetCoralLight,
      accentColor: AppColors.sunsetCoral,
      footer: AnimatedOpacity(
        opacity: canContinue ? 1.0 : 0.45,
        duration: const Duration(milliseconds: 180),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canContinue
                ? () => context.read<OnboardingService>().nextStep()
                : null,
            child: Text(context.l('Continue')),
          ),
        ),
      ),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _categories.map((cat) {
            return CategoryChip(
              label: context.l(cat.label),
              isSelected: selected.contains(cat.value),
              onTap: () =>
                  context.read<OnboardingService>().toggleCategory(cat.value),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: selected.length < _minRequired
              ? Text(
                  context.l('Select {count} more', {
                    'count': _minRequired - selected.length,
                  }),
                  key: const ValueKey('need_more'),
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0,
                  ),
                )
              : Text(
                  context.l('{count} selected', {'count': selected.length}),
                  key: const ValueKey('selected'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.fernGreen,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppTypography.fontFamily,
                  ),
                ),
        ),
      ],
    );
  }
}
