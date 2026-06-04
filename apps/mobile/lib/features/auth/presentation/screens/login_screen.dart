// login screen
// @params none

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/link_launcher.dart';
import '../../../../core/utils/snack.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  late final AnimationController _entranceCtrl;
  late final AnimationController _breathCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _agreedToTerms = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 560),
    )..forward();
    _breathCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entranceCtrl.dispose();
    _breathCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _breathCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      _breathCtrl.repeat(reverse: true);
    }
  }

  void _showAgreementSnack() {
    showWarningSnack(
      context,
      context.l('Accept the Privacy Policy and Terms of Service to continue.'),
    );
  }

  Future<void> _submit() async {
    if (!_agreedToTerms) {
      _showAgreementSnack();
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthService>();
    final email = _emailCtrl.text.trim();
    final sent = await auth.sendOtp(email: email);
    if (!mounted || !sent) return;
    context.push('/verify-email', extra: email);
  }

  Future<void> _googleSignIn() async {
    if (!_agreedToTerms) {
      _showAgreementSnack();
      return;
    }
    final auth = context.read<AuthService>();
    await auth.signInWithGoogle();
    // router redirect handles navigation after the auth state updates
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.select<AuthService, bool>((a) => a.isLoading);
    final error = context.select<AuthService, String?>((a) => a.error);

    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showErrorSnack(context, error);
        context.read<AuthService>().clearError();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF5FAF7),
              Color(0xFFFFFFFF),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth > 640 ? 430.0 : 520.0;
              return Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _BrandHeader(animation: _breathCtrl),
                            const SizedBox(height: AppSpacing.xxl),
                            _LoginPanel(
                              formKey: _formKey,
                              emailCtrl: _emailCtrl,
                              agreed: _agreedToTerms,
                              isLoading: isLoading,
                              onAgreementChanged: (value) =>
                                  setState(() => _agreedToTerms = value),
                              onSubmit: _submit,
                              onGoogle: _googleSignIn,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              context.tx('login.secureCopy'),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.josefinSans(
                                fontSize: 12,
                                height: 1.45,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.animation});
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final scale = 1.0 + animation.value * 0.025;
        return Column(
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.fernGreen.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Echoproof',
              style: GoogleFonts.josefinSans(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 5,
              runSpacing: 2,
              children: [
                _VerifiedClaimsStroke(
                  label: context.tx('login.subtitleLead'),
                ),
                Text(
                  context.tx('login.subtitleTail'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _VerifiedClaimsStroke extends StatefulWidget {
  const _VerifiedClaimsStroke({required this.label});
  final String label;

  @override
  State<_VerifiedClaimsStroke> createState() => _VerifiedClaimsStrokeState();
}

class _VerifiedClaimsStrokeState extends State<_VerifiedClaimsStroke>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _stroke;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    _stroke = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _stroke,
      builder: (context, child) {
        return CustomPaint(
          painter: _VerifiedClaimsStrokePainter(progress: _stroke.value),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          widget.label,
          style: GoogleFonts.josefinSans(
            fontSize: 14,
            color: AppColors.charcoal,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _VerifiedClaimsStrokePainter extends CustomPainter {
  const _VerifiedClaimsStrokePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = AppColors.fernGreenLight.withValues(alpha: 0.86)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.height * 0.48;

    final maxWidth = size.width * progress;
    final y = size.height * 0.62;
    final path = Path()
      ..moveTo(3, y)
      ..cubicTo(
        size.width * 0.28,
        y - 1.8,
        size.width * 0.62,
        y + 2.2,
        size.width - 3,
        y - 0.6,
      );

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, maxWidth, size.height));
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _VerifiedClaimsStrokePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.formKey,
    required this.emailCtrl,
    required this.agreed,
    required this.isLoading,
    required this.onAgreementChanged,
    required this.onSubmit,
    required this.onGoogle,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final bool agreed;
  final bool isLoading;
  final ValueChanged<bool> onAgreementChanged;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelAccent(isLoading: isLoading),
            const SizedBox(height: AppSpacing.lg),
            Text(context.tx('login.signIn'),
                style: AppTypography.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tx('login.emailHelp'),
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _EmailField(ctrl: emailCtrl, enabled: !isLoading),
            const SizedBox(height: AppSpacing.lg),
            _AgreementCheckbox(
              agreed: agreed,
              enabled: !isLoading,
              onChanged: onAgreementChanged,
            ),
            const SizedBox(height: AppSpacing.lg),
            _ContinueButton(
              isLoading: isLoading,
              enabled: agreed,
              onTap: onSubmit,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.borderSubtle)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'or',
                    style: GoogleFonts.josefinSans(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.borderSubtle)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _GoogleButton(
              isLoading: isLoading,
              enabled: agreed,
              onTap: onGoogle,
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelAccent extends StatefulWidget {
  const _PanelAccent({required this.isLoading});
  final bool isLoading;

  @override
  State<_PanelAccent> createState() => _PanelAccentState();
}

class _PanelAccentState extends State<_PanelAccent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final x = widget.isLoading ? _controller.value : 0.18;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1 + x * 2, 0),
                  end: Alignment(0.4 + x * 2, 0),
                  colors: [
                    AppColors.fernGreen.withValues(alpha: 0.14),
                    AppColors.fernGreen.withValues(alpha: 0.52),
                    AppColors.sunsetCoral.withValues(alpha: 0.24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmailField extends StatefulWidget {
  const _EmailField({required this.ctrl, required this.enabled});
  final TextEditingController ctrl;
  final bool enabled;

  @override
  State<_EmailField> createState() => _EmailFieldState();
}

class _EmailFieldState extends State<_EmailField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color:
              widget.enabled ? AppColors.surfaceSecondary : AppColors.softSand,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? AppColors.fernGreen : AppColors.borderSubtle,
            width: _focused ? 1.5 : 1,
          ),
        ),
        child: TextFormField(
          controller: widget.ctrl,
          enabled: widget.enabled,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          style: GoogleFonts.josefinSans(
            fontSize: 15,
            color: AppColors.charcoal,
          ),
          validator: (value) {
            final email = value?.trim() ?? '';
            if (email.isEmpty) return 'Enter your email';
            final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
            if (!valid) return 'Enter a valid email';
            return null;
          },
          decoration: InputDecoration(
            hintText: context.tx('login.emailHint'),
            hintStyle: GoogleFonts.josefinSans(
              fontSize: 14,
              color: AppColors.textTertiary,
            ),
            prefixIcon: Icon(
              Icons.alternate_email_rounded,
              size: 18,
              color: _focused ? AppColors.fernGreen : AppColors.textTertiary,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.isLoading,
    required this.enabled,
    required this.onTap,
  });

  final bool isLoading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final canTap = enabled && !isLoading;
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.52,
      duration: const Duration(milliseconds: 180),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: isLoading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.charcoal,
            disabledBackgroundColor: AppColors.charcoal,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: isLoading
                ? const _LiquidLoader(key: ValueKey('loader'))
                : Text(
                    canTap
                        ? context.tx('login.continueEmail')
                        : context.tx('login.continueEmail'),
                    key: const ValueKey('label'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.isLoading,
    required this.enabled,
    required this.onTap,
  });

  final bool isLoading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: enabled && !isLoading ? 1 : 0.52,
      duration: const Duration(milliseconds: 180),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.fernGreen,
                        ),
                      )
                    : const _AnimatedGoogleIcon(),
                const SizedBox(width: AppSpacing.md),
                Text(
                  context.tx('login.continueGoogle'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgreementCheckbox extends StatelessWidget {
  const _AgreementCheckbox({
    required this.agreed,
    required this.enabled,
    required this.onChanged,
  });

  final bool agreed;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: agreed,
            onChanged: enabled ? (value) => onChanged(value ?? false) : null,
            activeColor: AppColors.fernGreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            side: const BorderSide(color: AppColors.borderMedium),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: GoogleFonts.josefinSans(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
              children: [
                TextSpan(text: context.tx('login.termsPrefix')),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _InlineLink(
                    label: context.tx('login.terms'),
                    url: 'https://echoproof.online/terms',
                  ),
                ),
                TextSpan(text: ' ${context.l('and')} '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: _InlineLink(
                    label: context.tx('login.privacy'),
                    url: 'https://echoproof.online/privacy',
                  ),
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineLink extends StatelessWidget {
  const _InlineLink({required this.label, required this.url});
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showOpenLinkSheet(context, url: url, title: label),
      child: Text(
        label,
        style: GoogleFonts.josefinSans(
          fontSize: 12,
          color: AppColors.fernGreenDark,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.fernGreenDark,
        ),
      ),
    );
  }
}

class _AnimatedGoogleIcon extends StatefulWidget {
  const _AnimatedGoogleIcon();

  @override
  State<_AnimatedGoogleIcon> createState() => _AnimatedGoogleIconState();
}

class _AnimatedGoogleIconState extends State<_AnimatedGoogleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SvgPicture.asset(
        'assets/icons/google.svg',
        width: 20,
        height: 20,
      ),
    );
  }
}

class _LiquidLoader extends StatefulWidget {
  const _LiquidLoader({super.key});

  @override
  State<_LiquidLoader> createState() => _LiquidLoaderState();
}

class _LiquidLoaderState extends State<_LiquidLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 22,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _LiquidLoaderPainter(progress: _controller.value),
          );
        },
      ),
    );
  }
}

class _LiquidLoaderPainter extends CustomPainter {
  const _LiquidLoaderPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    final bgPaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    canvas.drawRRect(track, bgPaint);

    canvas.save();
    canvas.clipRRect(track);

    final wavePaint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFE8F5EE),
          Color(0xFF4CAF6E),
          Color(0xFFFFFFFF),
        ],
      ).createShader(Offset.zero & size);

    final path = Path();
    final waveHeight = size.height * 0.18;
    final base = size.height * (0.58 - math.sin(progress * math.pi * 2) * 0.05);
    path.moveTo(0, size.height);
    path.lineTo(0, base);
    for (double x = 0; x <= size.width; x += 1) {
      final y = base +
          math.sin((x / size.width * math.pi * 2) + progress * math.pi * 2) *
              waveHeight;
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, wavePaint);

    final glintPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final glintX = (progress * (size.width + 18)) - 9;
    canvas.drawLine(
      Offset(glintX, 4),
      Offset(glintX + 12, size.height - 4),
      glintPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LiquidLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
