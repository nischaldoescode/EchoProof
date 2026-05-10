import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../services/auth_service.dart';
import '../../../onboarding/presentation/services/onboarding_service.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.email});
  final String email;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = PinInputController();

  bool _isVerifying = false;
  bool _hasError = false;
  bool _canResend = false;
  int _resendSecs = 20;

  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
    _startTimer();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _canResend = false;
      _resendSecs = 20;
    });
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        if (_resendSecs > 0) {
          _resendSecs--;
          _tick();
        } else {
          _canResend = true;
        }
      });
    });
  }

  Future<void> _verify() async {
    final otp = _ctrl.text;
    if (otp.length != 6 || _isVerifying) return;
    setState(() {
      _isVerifying = true;
      _hasError = false;
    });

    final auth = context.read<AuthService>();
    final success = await auth.verifyOtp(
      email: widget.email,
      otp: otp,
    );

    if (!mounted) return;

    if (success) {
      if (auth.hasUsername) {
        context.go('/feed');
      } else {
        // context.read<OnboardingService>().reset();
        // context.go('/onboarding');
        context.go('/age-gender');
      }
    } else {
      // Trigger error state before clearing the field to avoid a
      // mid-animation rebuild caused by simultaneous setState + triggerError.
      _shakeCtrl.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      _ctrl.triggerError();
      await Future.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => context.pop(),
                      color: AppColors.charcoal,
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppColors.fernGreenLight,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.mark_email_unread_outlined,
                        size: 26,
                        color: AppColors.fernGreen,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    Text(
                      'Check your email',
                      style: GoogleFonts.josefinSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'We sent a 6-digit code to\n${widget.email}',
                      style: GoogleFonts.josefinSans(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xxl),

                    // shake wrapper
                    AnimatedBuilder(
                      animation: _shakeAnim,
                      builder: (_, child) {
                        final shake =
                            math.sin(_shakeAnim.value * math.pi * 4) * 8;
                        return Transform.translate(
                          offset: Offset(shake, 0),
                          child: child,
                        );
                      },
                      child: MaterialPinField(
                        length: 6,
                        pinController: _ctrl,
                        keyboardType: TextInputType.number,
                        enableAutofill: true,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        theme: MaterialPinTheme(
                          shape: MaterialPinShape.outlined,
                          cellSize: const Size(44, 54),
                          spacing: 8,
                          borderRadius: BorderRadius.circular(13),
                          borderColor: AppColors.borderSubtle,
                          focusedBorderColor: AppColors.fernGreen,
                          errorColor: AppColors.sunsetCoral,
                          fillColor: const Color(0xFFF0F4F2),
                          focusedFillColor: Colors.white,
                          filledFillColor: Colors.white,
                          textStyle: GoogleFonts.josefinSans(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.charcoal,
                          ),
                          entryAnimation: MaterialPinAnimation.scale,
                          enableErrorShake: true,
                        ),
                        onChanged: (v) {
                          if (_hasError) setState(() => _hasError = false);
                          if (v.length == 6) _verify();
                        },
                        onCompleted: (_) => _verify(),
                      ),
                    ),

                    // error message
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _hasError
                          ? Padding(
                              padding:
                                  const EdgeInsets.only(top: AppSpacing.sm),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 14, color: AppColors.sunsetCoral),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.read<AuthService>().error ??
                                        'Incorrect code. Please try again.',
                                    style: GoogleFonts.josefinSans(
                                      fontSize: 12,
                                      color: AppColors.sunsetCoral,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isVerifying ? null : _verify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.charcoal,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('Verify',
                                style: GoogleFonts.josefinSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                )),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    Center(
                      child: TextButton(
                        onPressed: _canResend
                            ? () {
                                context.read<AuthService>().resendOtp(
                                      email: widget.email,
                                    );
                                _startTimer();
                              }
                            : null,
                        child: Text(
                          _canResend
                              ? 'Resend code'
                              : 'Resend in ${_resendSecs}s',
                          style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            color: _canResend
                                ? AppColors.fernGreen
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
