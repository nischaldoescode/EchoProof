// email otp verification screen
// shown after signup before onboarding
// uses pin_code_fields package for animated OTP input

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../services/auth_service.dart';
import 'dart:math' as math;

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.email});
  final String email;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  String  _otp         = '';
  bool    _isVerifying = false;
  bool    _hasError    = false;
  bool    _canResend   = false;
  int     _resendTimer = 60;

  late final AnimationController _shakeController;
  late final Animation<double>   _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _startResendTimer();
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() { _canResend = false; _resendTimer = 60; });
    Future.delayed(const Duration(seconds: 1), _tickTimer);
  }

  void _tickTimer() {
    if (!mounted) return;
    setState(() {
      if (_resendTimer > 0) {
        _resendTimer--;
        Future.delayed(const Duration(seconds: 1), _tickTimer);
      } else {
        _canResend = true;
      }
    });
  }

  Future<void> _verify() async {
    if (_otp.length != 6 || _isVerifying) return;
    setState(() { _isVerifying = true; _hasError = false; });

    final auth    = context.read<AuthService>();
    final success = await auth.verifyEmailOtp(
      email: widget.email,
      otp:   _otp,
    );

    if (!mounted) return;

    if (success) {
      context.go('/permissions');
    } else {
      setState(() { _isVerifying = false; _hasError = true; });
      _shakeController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),

              // back button
              IconButton(
                icon:      const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
                color:     AppColors.charcoal,
              ),

              const SizedBox(height: AppSpacing.xxl),

              // icon
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.fernGreenLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 28, color: AppColors.fernGreen,
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              Text(
                'Check your email',
                style: GoogleFonts.josefinSans(
                  fontSize:   26,
                  fontWeight: FontWeight.w700,
                  color:      AppColors.charcoal,
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              Text(
                'We sent a 6-digit code to\n${widget.email}',
                style: GoogleFonts.josefinSans(
                  fontSize: 14,
                  color:    AppColors.textSecondary,
                  height:   1.5,
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),

              // OTP input
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (context, child) {
                  final shake = math.sin(_shakeAnim.value * math.pi * 4) * 8;
                  return Transform.translate(
                    offset: Offset(shake, 0),
                    child: child,
                  );
                },
                child: PinCodeTextField(
                  appContext:  context,
                  length:      6,
                  animationType: AnimationType.scale,
                  pinTheme: PinTheme(
                    shape:             PinCodeFieldShape.box,
                    borderRadius:      BorderRadius.circular(12),
                    fieldHeight:       52,
                    fieldWidth:        44,
                    activeFillColor:   Colors.white,
                    inactiveFillColor: const Color(0xFFF0F4F2),
                    selectedFillColor: Colors.white,
                    activeColor: _hasError
                        ? AppColors.sunsetCoral
                        : AppColors.fernGreen,
                    inactiveColor:   AppColors.borderSubtle,
                    selectedColor:   AppColors.fernGreen,
                    errorBorderColor: AppColors.sunsetCoral,
                  ),
                  enableActiveFill: true,
                  keyboardType:     TextInputType.number,
                  onChanged: (v) {
                    setState(() { _otp = v; _hasError = false; });
                    if (v.length == 6) _verify();
                  },
                  onCompleted: (_) => _verify(),
                ),
              ),

              if (_hasError)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppColors.sunsetCoral,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.read<AuthService>().error ?? 'incorrect code',
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          color:    AppColors.sunsetCoral,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: AppSpacing.xl),

              // verify button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_otp.length == 6 && !_isVerifying) ? _verify : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.charcoal,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white,
                          ),
                        )
                      : Text(
                          'Verify',
                          style: GoogleFonts.josefinSans(
                            fontSize:   15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // resend
              Center(
                child: TextButton(
                  onPressed: _canResend
                      ? () {
                          context.read<AuthService>().resendOtp(
                            email: widget.email,
                          );
                          _startResendTimer();
                        }
                      : null,
                  child: Text(
                    _canResend
                        ? 'Resend code'
                        : 'Resend in ${_resendTimer}s',
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
    );
  }
}
