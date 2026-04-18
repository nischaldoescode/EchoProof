// onboarding step 2: category selection
// user picks minimum 3 interest categories
// uses animated pill chips with tap feedback

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/category_chip.dart';
import '../widgets/onboarding_progress.dart';

class StepCategories extends ConsumerWidget {
  const StepCategories({super.key});

  static const int _minRequired = 3;

  static const _categories = [
    (label: 'Tech',           value: 'tech'),
    (label: 'Finance',        value: 'finance'),
    (label: 'Startups',       value: 'startups'),
    (label: 'Social Issues',  value: 'social_issues'),
    (label: 'Web3',           value: 'web3'),
    (label: 'AI',             value: 'ai'),
    (label: 'Gaming',         value: 'gaming'),
    (label: 'Education',      value: 'education'),
    (label: 'Other',          value: 'other'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingProvider).selectedCategories;
    final canContinue = selected.length >= _minRequired;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const OnboardingProgress(currentStep: 2, totalSteps: 5),
              const SizedBox(height: AppSpacing.xxl),

              Text(
                'What matters to you?',
                style: AppTypography.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Pick at least $_minRequired areas. Your feed will show echoes from these communities.',
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // category chips — animated wrap layout
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _categories.map((cat) {
                  final isSelected = selected.contains(cat.value);
                  return CategoryChip(
                    label: cat.label,
                    isSelected: isSelected,
                    onTap: () {
                      ref.read(onboardingProvider.notifier).toggleCategory(cat.value);
                    },
                  );
                }).toList(),
              ),

              const Spacer(),

              // selection counter
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selected.length < _minRequired
                    ? Text(
                        'Select ${_minRequired - selected.length} more',
                        key: const ValueKey('need_more'),
                        style: AppTypography.textTheme.bodySmall,
                      )
                    : Text(
                        '${selected.length} selected',
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

              // continue button
              AnimatedOpacity(
                opacity: canContinue ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 200),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canContinue
                        ? () => ref.read(onboardingProvider.notifier).nextStep()
                        : null,
                    child: const Text('Continue'),
                  ),
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