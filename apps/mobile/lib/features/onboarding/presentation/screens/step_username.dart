// onboarding step 3 anonymous username
// checks uniqueness against supabase users_public
// uses onboardingservice via provider no riverpod
// this is a stateful widget since it has local state for error/loading, and
// it also asks for a display name
import 'dart:async';

import 'package:echoproof/core/utils/snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/sanitizer.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding_story_frame.dart';
import '../../../auth/presentation/services/auth_service.dart';
import '../../../../core/utils/logger.dart';

class StepUsername extends StatefulWidget {
  const StepUsername({super.key});

  @override
  State<StepUsername> createState() => _StepUsernameState();
}

class _StepUsernameState extends State<StepUsername> {
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isChecking = false;
  bool _isSaving = false;
  bool _usernameOk = false;
  String? _usernameError;
  Timer? _usernameDebounce;
  int _usernameCheckVersion = 0;

  @override
  void initState() {
    super.initState();
    // pre-fill display name from google if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthService>();
      if (auth.googleDisplayName != null && _displayNameCtrl.text.isEmpty) {
        _displayNameCtrl.text = auth.googleDisplayName!;
      }
    });
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkUsername(String value) async {
    final version = ++_usernameCheckVersion;
    final v = Sanitizer.username(value);
    if (v.length < 3) {
      setState(() {
        _usernameOk = false;
        _usernameError = context.l('At least 3 characters');
        _isChecking = false;
      });
      return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
      setState(() {
        _usernameOk = false;
        _usernameError = context.l('Only letters, numbers, and underscores');
        _isChecking = false;
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _usernameError = null;
    });

    try {
      final client = Supabase.instance.client;
      final myId = client.auth.currentUser?.id;

      final row = await client
          .from('users_public')
          .select('id')
          .eq('username', v)
          .neq('id', myId ?? '')
          .maybeSingle();

      if (!mounted || version != _usernameCheckVersion) return;

      if (row != null) {
        setState(() {
          _usernameOk = false;
          _usernameError = context.l('Username taken');
          _isChecking = false;
        });
      } else {
        setState(() {
          _usernameOk = true;
          _usernameError = null;
          _isChecking = false;
        });
      }
    } catch (e) {
      if (!mounted || version != _usernameCheckVersion) return;
      setState(() {
        _usernameOk = false;
        _usernameError = null;
        _isChecking = false;
      });
    }
  }

  void _queueUsernameCheck(String value) {
    _usernameDebounce?.cancel();
    final sanitized = Sanitizer.username(value);

    // debounce remote checks so typing quickly does not create a burst of
    // requests. the version counter also prevents older responses from
    // overwriting the latest visible availability state.
    if (sanitized.length < 3) {
      _usernameCheckVersion++;
      setState(() {
        _usernameOk = false;
        _usernameError = null;
        _isChecking = false;
      });
      return;
    }

    setState(() {
      _usernameOk = false;
      _usernameError = null;
      _isChecking = true;
    });
    _usernameDebounce = Timer(
      const Duration(milliseconds: 320),
      () => _checkUsername(sanitized),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_usernameOk) return;

    setState(() => _isSaving = true);

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      final username = Sanitizer.username(_usernameCtrl.text);
      final displayName = Sanitizer.displayName(_displayNameCtrl.text);

      final onboarding = context.read<OnboardingService>();
      final authService = context.read<AuthService>();

      onboarding.setUsername(username);
      onboarding.setDisplayName(displayName);

      if (userId == null) throw Exception('not authenticated');

      await client
          .from('users_public')
          .update({
            'username': onboarding.username,
            'display_name': onboarding.displayName.isNotEmpty
                ? onboarding.displayName
                : onboarding.username,
          })
          .eq('id', userId);

      AppLogger.info('onboarding: username set to $username');

      if (!mounted) return;

      // mark username as set in both onboarding service and auth service
      onboarding.markUsernameSet();
      await authService.checkUsername();

      // advance to next step
      onboarding.advance();
    } catch (e) {
      AppLogger.error('onboarding: set username failed $e');
      if (mounted) {
        showErrorSnack(context, context.l('Failed to save. Please try again.'));
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final authService = context.read<AuthService>();
        final onboardingService = context.read<OnboardingService>();
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              context.l('Cancel setup?'),
              style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
            ),
            content: Text(
              context.l(
                'Your account won\'t be fully set up. You\'ll need to complete this next time.',
              ),
              style: GoogleFonts.josefinSans(fontSize: 14, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  context.l('Stay'),
                  style: GoogleFonts.josefinSans(color: AppColors.fernGreen),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.sunsetCoral,
                ),
                child: Text(
                  context.l('Leave'),
                  style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
        if (leave == true) {
          await authService.signOut();
          if (!context.mounted) return;
          onboardingService.reset();
          context.go('/login');
        }
      },
      child: Form(
        key: _formKey,
        child: OnboardingStoryFrame(
          currentStep: 4,
          totalSteps: 7,
          title: context.l('Now leave a handle, not a trail.'),
          body: context.l(
            'Your display name is friendly. Your username is the stable handle people can mention.',
          ),
          sceneIcon: Icons.alternate_email_rounded,
          sceneLabel: context.l('a public handle without public identity'),
          footer: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_usernameOk && !_isSaving) ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.charcoal,
                disabledBackgroundColor: AppColors.borderMedium,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      context.l('Continue'),
                      style: GoogleFonts.josefinSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          children: [
            Text(
              context.l('Display name'),
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _displayNameCtrl,
              maxLength: 50,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.josefinSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
              decoration: InputDecoration(
                hintText: context.l('Your name'),
                hintStyle: GoogleFonts.josefinSans(
                  fontSize: 15,
                  color: AppColors.textTertiary,
                ),
                filled: true,
                fillColor: AppColors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.fernGreen,
                    width: 2,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.sunsetCoral,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? context.l('Enter your name')
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l('Username'),
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _usernameCtrl,
              maxLength: 20,
              buildCounter:
                  (
                    _, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) => null,
              autocorrect: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                LengthLimitingTextInputFormatter(20),
              ],
              onChanged: _queueUsernameCheck,
              style: GoogleFonts.josefinSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
              decoration: InputDecoration(
                hintText: context.l('username'),
                hintStyle: GoogleFonts.josefinSans(
                  fontSize: 15,
                  color: AppColors.textTertiary,
                ),
                prefixText: '@',
                prefixStyle: GoogleFonts.josefinSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.fernGreen,
                ),
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
                    : _usernameOk
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.fernGreen,
                        size: 20,
                      )
                    : null,
                errorText: _usernameError,
                filled: true,
                fillColor: AppColors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.fernGreen,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.sunsetCoral),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.sunsetCoral,
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return context.l('Enter a username');
                }
                if (v.length < 3) {
                  return context.l('At least 3 characters');
                }
                if (!_usernameOk) {
                  return _usernameError ?? context.l('Check username');
                }
                return null;
              },
            ),
            if (_usernameOk && _usernameCtrl.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  context.l('Available!'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    color: AppColors.fernGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
