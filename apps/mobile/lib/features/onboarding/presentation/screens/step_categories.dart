// onboarding step 2 — category selection
// minimum 3 required
// uses OnboardingService via provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_progress.dart';
import '../widgets/category_chip.dart';

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

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.xl),
                    const OnboardingProgress(currentStep: 2, totalSteps: 5),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      context.l('What matters to you?'),
                      style: AppTypography.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l(
                        'Pick at least {count} areas. Your feed will show echoes from these communities.',
                        {'count': _minRequired},
                      ),
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: _categories.map((cat) {
                        return CategoryChip(
                          label: context.l(cat.label),
                          isSelected: selected.contains(cat.value),
                          onTap: () => context
                              .read<OnboardingService>()
                              .toggleCategory(cat.value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: AppSpacing.xxxl),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: selected.length < _minRequired
                          ? Text(
                              context.l('Select {count} more', {
                                'count': _minRequired - selected.length,
                              }),
                              key: const ValueKey('need_more'),
                              style: AppTypography.textTheme.bodySmall,
                            )
                          : Text(
                              context.l('{count} selected', {
                                'count': selected.length,
                              }),
                              key: const ValueKey('selected'),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.fernGreen,
                                fontWeight: FontWeight.w600,
                                fontFamily: AppTypography.fontFamily,
                              ),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AnimatedOpacity(
                      opacity: canContinue ? 1.0 : 0.4,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canContinue
                              ? () =>
                                  context.read<OnboardingService>().nextStep()
                              : null,
                          child: Text(context.l('Continue')),
                        ),
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
