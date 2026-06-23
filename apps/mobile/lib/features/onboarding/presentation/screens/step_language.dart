// onboarding step 0 language selector
// shown first in onboarding, before identity intro
// persists selected locale code to hive via onboardingservice.setlanguage()

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_story_frame.dart';
import 'package:flutter/services.dart';

class StepLanguage extends StatefulWidget {
  const StepLanguage({super.key});

  @override
  State<StepLanguage> createState() => _StepLanguageState();
}

class _StepLanguageState extends State<StepLanguage> {
  static const _languages = [
    ('English', '🇬🇧', 'en'),
    ('हिन्दी', '🇮🇳', 'hi'),
    ('தமிழ்', '🇮🇳', 'ta'),
    ('తెలుగు', '🇮🇳', 'te'),
    ('ಕನ್ನಡ', '🇮🇳', 'kn'),
    ('मराठी', '🇮🇳', 'mr'),
    ('বাংলা', '🇧🇩', 'bn'),
    ('Español', '🇪🇸', 'es'),
    ('Français', '🇫🇷', 'fr'),
    ('Deutsch', '🇩🇪', 'de'),
    ('العربية', '🇸🇦', 'ar'),
    ('中文', '🇨🇳', 'zh'),
  ];

  late String _selected;

  @override
  void initState() {
    super.initState();
    // pre-select whatever was saved previously, defaulting to english.
    _selected = context.read<OnboardingService>().language;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingStoryFrame(
      currentStep: 1,
      totalSteps: 7,
      title: context.tx('onboarding.languageTitle'),
      body: context.tx('onboarding.languageHelp'),
      sceneIcon: Icons.translate_rounded,
      sceneLabel: context.l('Your story starts in the language you choose.'),
      footer: _LanguageContinueButton(
        selected: _selected,
        onPressed: () {
          HapticFeedback.mediumImpact();
          final svc = context.read<OnboardingService>();
          svc.setLanguage(_selected);
          // wait one short beat so the selected language is visible before the
          // step changes. keeping this below a frame sequence avoids feeling
          // like the onboarding flow is blocked.
          Future.delayed(const Duration(milliseconds: 180), () {
            if (mounted) svc.nextStep();
          });
        },
      ),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width < 340
                ? 1
                : width > 520
                ? 3
                : 2;
            final aspectRatio = crossAxisCount == 1 ? 5.2 : 3.1;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _languages.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (context, i) {
                final lang = _languages[i];
                final isSelected = _selected == lang.$3;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selected = lang.$3);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.fernGreenLight
                            : AppColors.surfaceSecondary,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusMd,
                        ),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.fernGreen
                              : AppColors.borderSubtle,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Text(lang.$2, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              lang.$1,
                              style: AppTypography.textTheme.bodyMedium
                                  ?.copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? AppColors.fernGreenDark
                                        : AppColors.textPrimary,
                                    letterSpacing: 0,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: isSelected ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: const Icon(
                              Icons.check_circle_rounded,
                              size: 16,
                              color: AppColors.fernGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _LanguageContinueButton extends StatefulWidget {
  const _LanguageContinueButton({
    required this.selected,
    required this.onPressed,
  });

  final String selected;
  final VoidCallback onPressed;

  @override
  State<_LanguageContinueButton> createState() =>
      _LanguageContinueButtonState();
}

class _LanguageContinueButtonState extends State<_LanguageContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: widget.selected.isNotEmpty
              ? () async {
                  await _ctrl.forward();
                  await _ctrl.reverse();
                  widget.onPressed();
                }
              : null,
          child: Text(context.tx('common.continue')),
        ),
      ),
    );
  }
}
