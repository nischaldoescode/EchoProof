// onboarding step 5: optional first echo creation
// skip allowed — completes onboarding either way

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress.dart';
import '../../../echo/domain/entities/echo_entity.dart';
import '../../../echo/presentation/providers/create_echo_provider.dart';

class StepFirstEcho extends ConsumerStatefulWidget {
  const StepFirstEcho({super.key});

  @override
  ConsumerState<StepFirstEcho> createState() => _StepFirstEchoState();
}

class _StepFirstEchoState extends ConsumerState<StepFirstEcho> {
  final _controller = TextEditingController();
  EchoCategory? _selectedCategory;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    await ref.read(onboardingProvider.notifier).completeOnboarding();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty || _selectedCategory == null) return;
    final notifier = ref.read(createEchoProvider.notifier);
    notifier.setTitle(_controller.text.trim());
    notifier.setContent(_controller.text.trim());
    notifier.setCategory(_selectedCategory!);
    await notifier.submit();
    if (mounted) await ref.read(onboardingProvider.notifier).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = ref.watch(createEchoProvider).isSubmitting;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              const OnboardingProgress(currentStep: 5, totalSteps: 5),
              const SizedBox(height: AppSpacing.xxl),

              Text('Share your first Echo', style: AppTypography.textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Optional — you can always create one later from the feed.',
                style: AppTypography.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // echo text area
              TextField(
                controller: _controller,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(
                  hintText: 'What do you want the community to verify?',
                  alignLabelWithHint: true,
                ),
                style: AppTypography.textTheme.bodyMedium,
              ),

              const SizedBox(height: AppSpacing.lg),

              // quick category picker — horizontal scroll
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: EchoCategory.values.map((cat) {
                    final selected = _selectedCategory == cat;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.charcoal : AppColors.softSand,
                          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                          border: Border.all(
                            color: selected ? AppColors.charcoal : AppColors.borderSubtle,
                          ),
                        ),
                        child: Text(
                          cat.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? AppColors.white : AppColors.textPrimary,
                            fontFamily: AppTypography.fontFamily,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const Spacer(),

              // submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : _submit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                        )
                      : const Text('Publish and enter'),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // skip
              Center(
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip for now',
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
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