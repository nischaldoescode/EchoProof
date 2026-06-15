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
    _slide = Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
        );
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
    final hasPendingDeepLink =
        GoRouterState.of(context).uri.queryParameters['continue'] == '1';

    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showErrorSnack(context, error);
        context.read<AuthService>().clearError();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F4),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _breathCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _LoginBackdropPainter(progress: _breathCtrl.value),
                );
              },
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                final horizontal = isWide ? AppSpacing.xxl : AppSpacing.lg;
                final maxWidth = isWide ? 520.0 : 460.0;
                return Center(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      AppSpacing.xl,
                      horizontal,
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
                              if (hasPendingDeepLink) ...[
                                const _PendingDeepLinkBanner(),
                                const SizedBox(height: AppSpacing.md),
                              ],
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
                              const SizedBox(height: AppSpacing.xl),
                              _LoginFooter(
                                label: context.l('Your data is safe with us.'),
                                sublabel: context.tx('login.secureCopy'),
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
        ],
      ),
    );
  }
}

class _PendingDeepLinkBanner extends StatelessWidget {
  const _PendingDeepLinkBanner();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.fernGreenLight),
          boxShadow: [
            BoxShadow(
              color: AppColors.fernGreenDark.withValues(alpha: 0.08),
              blurRadius: 22,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.link_rounded,
                color: AppColors.fernGreenDark,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l('Sign in to open that echo'),
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
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

class _LoginBackdropPainter extends CustomPainter {
  const _LoginBackdropPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFEAF5EC), Color(0xFFF8FBF7), Color(0xFFFFFFFF)],
        stops: [0, 0.56, 1],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final canopy = Paint()
      ..color = const Color(0xFF8FC99E).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;
    final topPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * (0.11 + progress * 0.012))
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.06,
        size.width * 0.48,
        size.height * 0.15,
        size.width * 0.20,
        size.height * 0.08,
      )
      ..cubicTo(
        size.width * 0.10,
        size.height * 0.05,
        size.width * 0.04,
        size.height * 0.06,
        0,
        size.height * 0.04,
      )
      ..close();
    canvas.drawPath(topPath, canopy);

    final lowerMist = Paint()
      ..color = const Color(0xFFD8EFE1).withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final lowerPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, size.height * 0.86)
      ..cubicTo(
        size.width * 0.72,
        size.height * (0.91 - progress * 0.01),
        size.width * 0.38,
        size.height * 0.83,
        0,
        size.height * 0.91,
      )
      ..close();
    canvas.drawPath(lowerPath, lowerMist);

    _paintLeafCluster(
      canvas,
      origin: Offset(size.width * 0.10, size.height * 0.02),
      scale: size.shortestSide * 0.0028,
      rotate: -0.18,
      opacity: 0.18,
    );
    _paintLeafCluster(
      canvas,
      origin: Offset(size.width * 0.90, size.height * 0.06),
      scale: size.shortestSide * 0.0025,
      rotate: 2.78,
      opacity: 0.14,
    );
    _paintLeafCluster(
      canvas,
      origin: Offset(size.width * 0.04, size.height * 0.88),
      scale: size.shortestSide * 0.0022,
      rotate: 0.48,
      opacity: 0.10,
    );
  }

  void _paintLeafCluster(
    Canvas canvas, {
    required Offset origin,
    required double scale,
    required double rotate,
    required double opacity,
  }) {
    final stemPaint = Paint()
      ..color = const Color(0xFF3F7A63).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final leafPaint = Paint()
      ..color = const Color(0xFF4CAF6E).withValues(alpha: opacity * 0.72)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(rotate);
    canvas.scale(scale * 90);

    final stem = Path()
      ..moveTo(0, 0)
      ..cubicTo(36, 26, 70, 70, 88, 122);
    canvas.drawPath(stem, stemPaint);

    for (var i = 0; i < 7; i++) {
      final t = i / 6;
      final x = 14 + t * 68;
      final y = 12 + t * 96;
      final side = i.isEven ? -1.0 : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(side * (0.82 - t * 0.28));
      final leaf = Path()
        ..moveTo(0, 0)
        ..cubicTo(20, -12, 44, -10, 58, 5)
        ..cubicTo(36, 16, 16, 14, 0, 0);
      canvas.drawPath(leaf, leafPaint);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoginBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _LoginSubtitle extends StatelessWidget {
  const _LoginSubtitle();

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.josefinSans(
      fontSize: 18,
      height: 1.48,
      color: const Color(0xFF667085),
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: '${context.tx('login.journeyLine')}\n'),
          TextSpan(text: context.tx('login.journeyPrefix')),
          TextSpan(
            text: context.tx('login.journeyTrust'),
            style: style.copyWith(
              color: AppColors.fernGreenDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: context.tx('login.journeySuffix')),
        ],
      ),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter({required this.label, required this.sublabel});
  final String label;
  final String sublabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.verified_user_outlined,
              size: 22,
              color: AppColors.fernGreenDark,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.josefinSans(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          sublabel,
          textAlign: TextAlign.center,
          style: GoogleFonts.josefinSans(
            fontSize: 14,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
      ],
    );
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
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 18.0 : 22.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        18,
        horizontalPadding,
        20,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.78),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B332B).withValues(alpha: 0.10),
            blurRadius: 42,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelAccent(isLoading: isLoading),
            const SizedBox(height: 26),
            Text(
              context.tx('login.signIn'),
              style: GoogleFonts.josefinSans(
                fontSize: width < 360 ? 30 : 32,
                height: 1.02,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF183D35),
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            const _LoginSubtitle(),
            const SizedBox(height: 24),
            _EmailField(ctrl: emailCtrl, enabled: !isLoading),
            const SizedBox(height: 16),
            _AgreementCheckbox(
              agreed: agreed,
              enabled: !isLoading,
              onChanged: onAgreementChanged,
            ),
            const SizedBox(height: 18),
            _ContinueButton(
              isLoading: isLoading,
              enabled: agreed,
              onTap: onSubmit,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.borderSubtle)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
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
            const SizedBox(height: 18),
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
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 5,
          width: 132,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final value = widget.isLoading
                  ? 0.40 + math.sin(_controller.value * math.pi * 2) * 0.18
                  : 0.50;
              return CustomPaint(
                painter: _PanelAccentPainter(
                  progress: value.clamp(0.28, 0.72).toDouble(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PanelAccentPainter extends CustomPainter {
  const _PanelAccentPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = AppColors.fernGreen.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final fg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF2D7A4A), Color(0xFF4CAF6E)],
      ).createShader(Offset.zero & size);
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, radius), bg);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * progress, size.height),
        radius,
      ),
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _PanelAccentPainter oldDelegate) {
    return oldDelegate.progress != progress;
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
          color: widget.enabled ? Colors.white : AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: _focused
                ? AppColors.fernGreen.withValues(alpha: 0.78)
                : const Color(0xFFDADDD8),
            width: _focused ? 1.6 : 1.2,
          ),
          boxShadow: [
            if (_focused)
              BoxShadow(
                color: AppColors.fernGreen.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: TextFormField(
          controller: widget.ctrl,
          enabled: widget.enabled,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            color: AppColors.charcoal,
            fontWeight: FontWeight.w600,
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
              fontSize: 18,
              color: const Color(0xFF89909B),
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(
              Icons.mail_outline_rounded,
              size: 27,
              color: _focused
                  ? AppColors.fernGreenDark
                  : const Color(0xFF7C8490),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
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
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.52,
      duration: const Duration(milliseconds: 180),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF2C8B53), Color(0xFF258246)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.fernGreenDark.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: isLoading
                  ? const Center(
                      key: ValueKey('loader'),
                      child: _LiquidLoader(),
                    )
                  : Stack(
                      key: const ValueKey('label'),
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: Text(
                            context.tx('login.continueEmail'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.josefinSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          end: 22,
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white.withValues(alpha: 0.96),
                            size: 27,
                          ),
                        ),
                      ],
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
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: const Color(0xFFDADDD8), width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B332B).withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
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
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF737B86),
                    letterSpacing: 0,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(!agreed) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: agreed ? AppColors.fernGreen : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: agreed ? AppColors.fernGreen : const Color(0xFFBFC5CE),
                width: 1.5,
              ),
              boxShadow: [
                if (agreed)
                  BoxShadow(
                    color: AppColors.fernGreen.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              child: agreed
                  ? const Icon(
                      Icons.check_rounded,
                      key: ValueKey('checked'),
                      size: 16,
                      color: Colors.white,
                    )
                  : const SizedBox(key: ValueKey('empty')),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.josefinSans(
                  fontSize: 15,
                  color: const Color(0xFF737B86),
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
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
                ],
              ),
            ),
          ),
        ],
      ),
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
          fontSize: 15,
          color: AppColors.fernGreenDark,
          fontWeight: FontWeight.w800,
          decoration: TextDecoration.none,
          letterSpacing: 0,
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
    _scale = Tween<double>(
      begin: 0.92,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
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
      child: SvgPicture.asset('assets/icons/google.svg', width: 20, height: 20),
    );
  }
}

class _LiquidLoader extends StatefulWidget {
  const _LiquidLoader();

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
        colors: [Color(0xFFE8F5EE), Color(0xFF4CAF6E), Color(0xFFFFFFFF)],
      ).createShader(Offset.zero & size);

    final path = Path();
    final waveHeight = size.height * 0.18;
    final base = size.height * (0.58 - math.sin(progress * math.pi * 2) * 0.05);
    path.moveTo(0, size.height);
    path.lineTo(0, base);
    for (double x = 0; x <= size.width; x += 1) {
      final y =
          base +
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
