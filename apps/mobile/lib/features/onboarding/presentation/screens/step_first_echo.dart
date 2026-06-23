// onboarding step 6 optional first echo creation
// skip is allowed completes onboarding either way
// char limit: 308 (twitter free = 280, +10% = 308)
// live counter with colour shift near/at limit

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_story_frame.dart';
import '../../../echo/domain/entities/echo_entity.dart';
import '../../../echo/presentation/services/create_echo_service.dart';
import '../../../../core/utils/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../auth/presentation/services/auth_service.dart';

class StepFirstEcho extends StatefulWidget {
  const StepFirstEcho({super.key});

  @override
  State<StepFirstEcho> createState() => _StepFirstEchoState();
}

class _StepFirstEchoState extends State<StepFirstEcho> {
  static const int _maxChars = 308; // 10% above twitter free (280)

  final _controller = TextEditingController();
  EchoCategory? _selectedCategory;
  bool _skipLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    setState(() => _skipLoading = true);
    try {
      await context.read<OnboardingService>().completeOnboarding(
        authService: context.read<AuthService>(),
      );
    } catch (e) {
      AppLogger.error('first echo: skip failed $e');
    } finally {
      if (mounted) setState(() => _skipLoading = false);
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _selectedCategory == null) return;
    if (text.length > _maxChars) return;

    final createService = context.read<CreateEchoService>();
    createService.setTitle(
      text.length > 80 ? '${text.substring(0, 80)}...' : text,
    );
    createService.setContent(text);
    createService.setCategory(_selectedCategory!);

    try {
      await createService.submit();
    } catch (e) {
      AppLogger.error('first echo: echo submit failed $e');
    }

    if (mounted) {
      try {
        await context.read<OnboardingService>().completeOnboarding(
          authService: context.read<AuthService>(),
        );
      } catch (e) {
        AppLogger.error('first echo: complete onboarding failed $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final createService = context.watch<CreateEchoService>();
    final onboardingService = context.watch<OnboardingService>();

    return Stack(
      children: [
        OnboardingStoryFrame(
          currentStep: 7,
          totalSteps: 7,
          title: context.l('Open with a small signal.'),
          body: context.l(
            'Share one claim for the community to verify, or enter quietly and post later.',
          ),
          sceneIcon: Icons.edit_note_rounded,
          sceneLabel: context.l('your first echo can be a draft of curiosity'),
          sceneBackground: AppColors.surfaceSecondary,
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final canPost =
                      value.text.trim().isNotEmpty &&
                      _selectedCategory != null &&
                      value.text.length <= _maxChars &&
                      !createService.isSubmitting;

                  return AnimatedOpacity(
                    opacity: canPost ? 1.0 : 0.45,
                    duration: const Duration(milliseconds: 180),
                    child: ElevatedButton(
                      onPressed: canPost ? _submit : null,
                      child: createService.isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.white,
                              ),
                            )
                          : Text(context.l('Publish and enter')),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: _skipLoading ? null : _skip,
                  child: _skipLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textSecondary,
                          ),
                        )
                      : Text(
                          context.l('Skip for now'),
                          style: AppTypography.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                            letterSpacing: 0,
                          ),
                        ),
                ),
              ),
            ],
          ),
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final len = value.text.length;
                final remaining = _maxChars - len;
                final isOver = remaining < 0;
                final isNear = remaining <= 30 && !isOver;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _controller,
                      maxLines: 5,
                      maxLength: _maxChars,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      buildCounter:
                          (
                            _, {
                            required currentLength,
                            required isFocused,
                            maxLength,
                          }) => const SizedBox.shrink(),
                      decoration: InputDecoration(
                        hintText: context.l(
                          'What do you want the community to verify?',
                        ),
                        alignLabelWithHint: true,
                        filled: true,
                        fillColor: AppColors.white,
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppColors.fernGreen,
                            width: 2,
                          ),
                        ),
                      ),
                      style: AppTypography.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isNear || isOver)
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              value: (len / _maxChars).clamp(0.0, 1.0),
                              strokeWidth: 2.5,
                              backgroundColor: AppColors.borderSubtle,
                              color: isOver
                                  ? AppColors.sunsetCoral
                                  : AppColors.statusControversial,
                            ),
                          ),
                        if (isNear || isOver) const SizedBox(width: 6),
                        Text(
                          isOver ? '$remaining' : '$len / $_maxChars',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: (isOver || isNear)
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: isOver
                                ? AppColors.sunsetCoral
                                : isNear
                                ? AppColors.statusControversial
                                : AppColors.textTertiary,
                            fontFamily: AppTypography.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: EchoCategory.values.map((cat) {
                  final selected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.charcoal
                                : AppColors.surfaceSecondary,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            border: Border.all(
                              color: selected
                                  ? AppColors.charcoal
                                  : AppColors.borderSubtle,
                            ),
                          ),
                          child: Text(
                            context.l(cat.displayName),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? AppColors.white
                                  : AppColors.textPrimary,
                              fontFamily: AppTypography.fontFamily,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        if (_skipLoading || onboardingService.isSubmitting)
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: (_skipLoading || onboardingService.isSubmitting)
                  ? 1.0
                  : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: Colors.white.withValues(alpha: 0.85),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.fernGreen,
                        strokeWidth: 2.5,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        context.l('Setting up your account...'),
                        style: GoogleFonts.josefinSans(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
