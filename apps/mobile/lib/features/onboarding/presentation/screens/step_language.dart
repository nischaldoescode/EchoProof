// onboarding step: language selector
// shown before step 1 (identity intro) — step 0
// persists selected locale to Hive + updates app locale via provider

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_progress.dart';

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

  String _selected = 'en';

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
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
                  const SizedBox(height: AppSpacing.xl),
                  // No progress bar on language step — it's step 0
                  Text(
                    'Choose your language',
                    style: AppTypography.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'You can change this any time in settings.',
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
                        childAspectRatio: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemBuilder: (context, i) {
                        final lang = _languages[i];
                        final isSelected = _selected == lang.$3;
                        return GestureDetector(
                          onTap: () => setState(() => _selected = lang.$3),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.fernGreenLight
                                  : AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.fernGreen
                                    : Colors.transparent,
                                width: 1.5,
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
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        // persist language
                        context
                            .read<OnboardingService>()
                            .setLanguage(_selected);
                        context.read<OnboardingService>().nextStep();
                      },
                      child: const Text('Continue'),
                    ),
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