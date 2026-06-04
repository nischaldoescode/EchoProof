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
import 'package:flutter/services.dart';

class StepLanguage extends StatefulWidget {
  const StepLanguage({super.key});

  @override
  State<StepLanguage> createState() => _StepLanguageState();
}

class _StepLanguageState extends State<StepLanguage>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

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
    // pre-select whatever was saved previously (defaults to 'en')
    _selected = context.read<OnboardingService>().language;

    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    context.tx('onboarding.languageTitle'),
                    style: AppTypography.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.tx('onboarding.languageHelp'),
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Expanded(
                    child: GridView.builder(
                      itemCount: _languages.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 3.2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, i) {
                        final lang = _languages[i];
                        final isSelected = _selected == lang.$3;
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _selected = lang.$3);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                            decoration: BoxDecoration(
                              // use softsand (already in appcolors) for unselected
                              color: isSelected
                                  ? AppColors.fernGreenLight
                                  : AppColors.softSand,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.fernGreen
                                    : AppColors.borderSubtle,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Text(lang.$2,
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    lang.$1,
                                    style: AppTypography.textTheme.bodyMedium
                                        ?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? AppColors.fernGreen
                                          : AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: AppColors.fernGreen,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _LanguageContinueButton(
                    selected: _selected,
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      final svc = context.read<OnboardingService>();
                      svc.setLanguage(_selected);
                      // brief delay so the locale rebuild animates before
                      // advancing the step gives the user visual feedback
                      // that the language actually changed
                      Future.delayed(const Duration(milliseconds: 350), () {
                        if (mounted) svc.nextStep();
                      });
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
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
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
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
