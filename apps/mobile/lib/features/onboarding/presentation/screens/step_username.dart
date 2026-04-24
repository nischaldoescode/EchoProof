// onboarding step 3 — anonymous username
// checks uniqueness against supabase users_public
// uses OnboardingService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_progress.dart';
import '../../../../core/utils/username_validator.dart';
import 'package:go_router/go_router.dart';

class StepUsername extends StatefulWidget {
  const StepUsername({super.key});

  @override
  State<StepUsername> createState() => _StepUsernameState();
}

class _StepUsernameState extends State<StepUsername> {
  final _controller = TextEditingController();
  String? _errorText;
  bool _isChecking = false;

  static const _adjectives = [
    'quiet',
    'silent',
    'swift',
    'calm',
    'bold',
    'clear',
    'sharp',
    'bright',
    'deep',
    'true',
  ];
  static const _nouns = [
    'signal',
    'wave',
    'echo',
    'voice',
    'proof',
    'mark',
    'trace',
    'lens',
    'beam',
    'node',
  ];

  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _generateSuggestions();
    final saved = context.read<OnboardingService>().username;
    if (saved.isNotEmpty) _controller.text = saved;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _generateSuggestions() {
    final rng = Random();
    setState(() {
      _suggestions = List.generate(3, (_) {
        final adj = _adjectives[rng.nextInt(_adjectives.length)];
        final noun = _nouns[rng.nextInt(_nouns.length)];
        final num = rng.nextInt(900) + 100;
        return '${adj}_${noun}_$num';
      });
    });
  }

  Future<void> _checkAndContinue() async {
    final username = _controller.text.trim().toLowerCase();

    final validationError = UsernameValidator.validate(username);
    if (validationError != null) {
      setState(() => _errorText = validationError);
      return;
    }

    setState(() {
      _isChecking = true;
      _errorText = null;
    });

    try {
      final client = Supabase.instance.client;
      final result = await client
          .from('users_public')
          .select('id')
          .eq('username', username)
          .maybeSingle();

      if (result != null) {
        if (!mounted) return;
        setState(() {
          _isChecking = false;
          _errorText = 'username already taken, try another';
        });
        return;
      }

      if (!mounted) return;
      context.read<OnboardingService>().setUsername(username);
      context.read<OnboardingService>().nextStep();

      // go to age/gender step instead of generic nextStep
      if (mounted) {
        context.read<OnboardingService>().setUsername(username);
        context.push('/age-gender');
      }
    } catch (_) {
      setState(() {
        _isChecking = false;
        _errorText = 'could not check username, try again';
      });
    }
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
              const OnboardingProgress(currentStep: 3, totalSteps: 5),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Choose your alias',
                style: AppTypography.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This is your public identity. Keep it anonymous — never use your real name.',
                style: AppTypography.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              TextField(
                controller: _controller,
                onChanged: (_) => setState(() => _errorText = null),
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: 'your_alias',
                  prefixText: '@',
                  errorText: _errorText,
                  suffixIcon: _isChecking
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.fernGreen,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Suggestions',
                style: AppTypography.textTheme.labelLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ..._suggestions.map((s) => GestureDetector(
                        onTap: () {
                          _controller.text = s;
                          setState(() => _errorText = null);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.softSand,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusFull,
                            ),
                            border: Border.all(color: AppColors.borderSubtle),
                          ),
                          child: Text(
                            '@$s',
                            style: AppTypography.textTheme.labelLarge,
                          ),
                        ),
                      )),
                  GestureDetector(
                    onTap: _generateSuggestions,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.softSand,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusFull,
                        ),
                        border: Border.all(color: AppColors.borderSubtle),
                      ),
                      child: const Icon(
                        Icons.refresh,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _checkAndContinue,
                  child: const Text('Continue'),
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
