// onboarding step 4 — trust tier explanation
// animated tier ladder reveals
// uses OnboardingService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_progress.dart';

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
      label:       'Unverified',
      description: 'Default starting level',
      weight:      1,
      color:       AppColors.textTertiary,
      bg:          AppColors.softSand,
    ),
    (
      label:       'Low',
      description: 'Active, not yet verified',
      weight:      2,
      color:       AppColors.textSecondary,
      bg:          AppColors.softSand,
    ),
    (
      label:       'Medium',
      description: 'Consistent, helpful contributions',
      weight:      3,
      color:       AppColors.fernGreenDark,
      bg:          AppColors.fernGreenLight,
    ),
    (
      label:       'High',
      description: 'Identity verified + trusted',
      weight:      4,
      color:       AppColors.fernGreenDark,
      bg:          AppColors.fernGreenLight,
    ),
    (
      label:       'Elite',
      description: 'Top contributors — 5x vote weight',
      weight:      5,
      color:       AppColors.fernGreenDark,
      bg:          AppColors.fernGreenLight,
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
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const OnboardingProgress(currentStep: 4, totalSteps: 5),
              const SizedBox(height: AppSpacing.xxl),

              Text(
                'Your interactions shape truth.',
                style: AppTypography.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Higher trust tier = more weight. Votes from elite users move echoes more than unverified ones.',
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              Expanded(
                child: ListView.builder(
                  physics:   const NeverScrollableScrollPhysics(),
                  itemCount: _tiers.length,
                  itemBuilder: (context, i) {
                    final start = i / _tiers.length;
                    final end   = (i + 1) / _tiers.length;
                    final anim  = Tween<double>(begin: 0, end: 1).animate(
                      CurvedAnimation(
                        parent: _ladderController,
                        curve:  Interval(start, end, curve: Curves.easeOut),
                      ),
                    );
                    final tier = _tiers[i];

                    return AnimatedBuilder(
                      animation: anim,
                      builder: (context, child) => Opacity(
                        opacity: anim.value,
                        child: Transform.translate(
                          offset: Offset((1 - anim.value) * 30, 0),
                          child:  child,
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: tier.bg,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width:  32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: tier.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${tier.weight}x',
                                  style: TextStyle(
                                    fontSize:   11,
                                    fontWeight: FontWeight.w700,
                                    color:      tier.color,
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
                                    tier.label,
                                    style: TextStyle(
                                      fontSize:   13,
                                      fontWeight: FontWeight.w600,
                                      color:      tier.color,
                                      fontFamily: AppTypography.fontFamily,
                                    ),
                                  ),
                                  Text(
                                    tier.description,
                                    style: AppTypography.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      context.read<OnboardingService>().nextStep(),
                  child: const Text('Understood'),
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