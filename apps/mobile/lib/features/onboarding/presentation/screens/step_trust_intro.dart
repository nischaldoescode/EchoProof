// onboarding step 4 trust tier explanation
// animated tier ladder reveals
// uses onboardingservice via provider no riverpod

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_story_frame.dart';

class StepTrustIntro extends StatefulWidget {
  const StepTrustIntro({super.key});

  @override
  State<StepTrustIntro> createState() => _StepTrustIntroState();
}

class _StepTrustIntroState extends State<StepTrustIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ladderController;

  static const _tiers = [
    (
      label: 'Unverified',
      description: 'Default starting level',
      weight: 1,
      color: AppColors.textTertiary,
      bg: AppColors.softSand,
    ),
    (
      label: 'Low',
      description: 'Active, not yet verified',
      weight: 2,
      color: AppColors.textSecondary,
      bg: AppColors.softSand,
    ),
    (
      label: 'Medium',
      description: 'Consistent, helpful contributions',
      weight: 3,
      color: AppColors.fernGreenDark,
      bg: AppColors.fernGreenLight,
    ),
    (
      label: 'High',
      description: 'Identity verified + trusted',
      weight: 4,
      color: AppColors.fernGreenDark,
      bg: AppColors.fernGreenLight,
    ),
    (
      label: 'Elite',
      description: 'Top contributors — 5x vote weight',
      weight: 5,
      color: AppColors.fernGreenDark,
      bg: AppColors.fernGreenLight,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ladderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _ladderController.forward();
    });
  }

  @override
  void dispose() {
    _ladderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return OnboardingStoryFrame(
      currentStep: 5,
      totalSteps: 7,
      title: context.l('Every reaction has weight.'),
      body: context.l(
        'Your trust tier changes how strongly your signals move a claim. Better proof and better calls earn stronger weight.',
      ),
      sceneIcon: Icons.stacked_line_chart_rounded,
      sceneLabel: context.l('trust moves from quiet signal to stronger weight'),
      footer: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => context.read<OnboardingService>().nextStep(),
          child: Text(context.l('Understood')),
        ),
      ),
      children: [
        ...List.generate(_tiers.length, (i) {
          final start = i / _tiers.length;
          final end = (i + 1) / _tiers.length;
          final anim = reduceMotion
              ? const AlwaysStoppedAnimation<double>(1)
              : Tween<double>(begin: 0, end: 1).animate(
                  CurvedAnimation(
                    parent: _ladderController,
                    curve: Interval(start, end, curve: Curves.easeOutCubic),
                  ),
                );
          final tier = _tiers[i];

          return AnimatedBuilder(
            animation: anim,
            builder: (context, child) {
              final value = anim.value.clamp(0.0, 1.0).toDouble();
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset((1 - value) * 18, 0),
                  child: child,
                ),
              );
            },
            child: Container(
              margin: EdgeInsets.only(
                bottom: i == _tiers.length - 1 ? 0 : AppSpacing.sm,
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: tier.bg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: tier.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${tier.weight}x',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tier.color,
                          fontFamily: AppTypography.fontFamily,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l(tier.label),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tier.color,
                            fontFamily: AppTypography.fontFamily,
                          ),
                        ),
                        Text(
                          context.l(tier.description),
                          style: AppTypography.textTheme.bodySmall?.copyWith(
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
        }),
      ],
    );
  }
}
