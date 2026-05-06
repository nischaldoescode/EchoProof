import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
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

  late final AnimationController _bgCtrl;
  late final AnimationController _cardCtrl;
  late final AnimationController _particleCtrl;

  late final Animation<double> _cardScale;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;

  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _cardScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));

    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));

    final rng = math.Random();
    _particles.addAll(List.generate(18, (_) => _Particle.random(rng)));
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgCtrl.dispose();
    _cardCtrl.dispose();
    _particleCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _bgCtrl.stop();
      _particleCtrl.stop();
    } else if (state == AppLifecycleState.resumed) {
      _bgCtrl.repeat(reverse: true);
      _particleCtrl.repeat();
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthService>();
    final email = _emailCtrl.text.trim();

    final sent = await auth.sendOtp(email: email);
    if (!mounted) return;
    if (sent) context.push('/verify-email', extra: email);
  }

  Future<void> _googleSignIn() async {
    final auth = context.read<AuthService>();
    final success = await auth.signInWithGoogle();
    if (!mounted || !success) return;
    // router redirect handles navigation based on hasUsername
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;

    // watch only what we need — avoids full rebuild on unrelated changes
    final isLoading = context.select<AuthService, bool>((a) => a.isLoading);
    final error = context.select<AuthService, String?>((a) => a.error);

    // show error snack
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(error, style: GoogleFonts.josefinSans(fontSize: 13)),
            backgroundColor: AppColors.sunsetCoral,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 88, left: 16, right: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 3),
          ));
        context.read<AuthService>().clearError();
      });
    }

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_bgCtrl, _particleCtrl]),
        builder: (ctx, _) {
          final bg1 = Color.lerp(
              const Color(0xFFE8F5EE), const Color(0xFFF0FAF5), _bgCtrl.value)!;
          final bg2 = Color.lerp(
              const Color(0xFFFAF7F2), const Color(0xFFEDF9F3), _bgCtrl.value)!;

          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bg1, bg2],
              ),
            ),
            child: Stack(
              children: [
                // floating particles
                ...List.generate(_particles.length, (i) {
                  final p = _particles[i];
                  final phase = (_particleCtrl.value + p.offset) % 1.0;
                  return Positioned(
                    left: p.startX * size.width,
                    top: p.startY * size.height +
                        math.sin(phase * math.pi * 2) * 28 * p.amplitude,
                    child: Opacity(
                      opacity: 0.12 + 0.08 * math.sin(phase * math.pi),
                      child: Container(
                        width: p.size,
                        height: p.size,
                        decoration: BoxDecoration(
                          color: p.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),

                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? size.width * 0.15 : 24,
                        vertical: 32,
                      ),
                      child: Column(
                        children: [
                          // logo + title
                          AnimatedBuilder(
                            animation: _cardCtrl,
                            builder: (_, child) => FadeTransition(
                              opacity: _titleFade,
                              child: SlideTransition(
                                position: _titleSlide,
                                child: child,
                              ),
                            ),
                            child: Column(
                              children: [
                                _AnimatedLogo(ctrl: _particleCtrl),
                                const SizedBox(height: 20),
                                _TypewriterText(
                                  text: 'Echoproof',
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.charcoal,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _Dot(delay: 0),
                                    const SizedBox(width: 8),
                                    Text(
                                      'truth, verified by community',
                                      style: GoogleFonts.josefinSans(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _Dot(delay: 0.3),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          // form card
                          AnimatedBuilder(
                            animation: _cardCtrl,
                            builder: (_, child) => FadeTransition(
                              opacity: _cardFade,
                              child: SlideTransition(
                                position: _cardSlide,
                                child: ScaleTransition(
                                  scale: _cardScale,
                                  child: child,
                                ),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.93),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.fernGreen
                                        .withValues(alpha: 0.07),
                                    blurRadius: 32,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome to Echoproof',
                                      style: GoogleFonts.josefinSans(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.charcoal,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      "Enter your email. We'll send a one-time code to sign in or create your account.",
                                      style: GoogleFonts.josefinSans(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    _EmailField(ctrl: _emailCtrl),
                                    const SizedBox(height: 18),
                                    _ContinueButton(
                                      isLoading: isLoading,
                                      onTap: _submit,
                                    ),
                                    const SizedBox(height: 18),
                                    Row(children: [
                                      const Expanded(child: Divider()),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12),
                                        child: Text(
                                          'or',
                                          style: GoogleFonts.josefinSans(
                                            fontSize: 12,
                                            color: AppColors.textTertiary,
                                          ),
                                        ),
                                      ),
                                      const Expanded(child: Divider()),
                                    ]),
                                    const SizedBox(height: 18),
                                    _GoogleButton(
                                      isLoading: isLoading,
                                      onTap: _googleSignIn,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 28),

                          // feature badges — use Wrap to prevent overflow
                          AnimatedBuilder(
                            animation: _particleCtrl,
                            builder: (_, __) {
                              const badges = [
                                (Icons.verified_outlined, 'Community verified'),
                                (Icons.lock_outlined, 'End-to-end encrypted'),
                                (Icons.link_outlined, 'Permanent records'),
                              ];
                              return Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 6,
                                runSpacing: 6,
                                children: List.generate(badges.length, (i) {
                                  final phase =
                                      (_particleCtrl.value + i * 0.33) % 1.0;
                                  final dy = math.sin(phase * math.pi * 2) * 3;
                                  return Transform.translate(
                                    offset: Offset(0, dy),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.8),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: AppColors.borderSubtle),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            badges[i].$1,
                                            size: 12,
                                            color: AppColors.fernGreen,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            badges[i].$2,
                                            style: GoogleFonts.josefinSans(
                                              fontSize: 10,
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── sub-widgets ────────────────────────────────────────────────────────────

class _EmailField extends StatefulWidget {
  const _EmailField({required this.ctrl});
  final TextEditingController ctrl;

  @override
  State<_EmailField> createState() => _EmailFieldState();
}

class _EmailFieldState extends State<_EmailField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _focused ? Colors.white : const Color(0xFFF8FAF9),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? AppColors.fernGreen : AppColors.borderSubtle,
            width: _focused ? 2 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: AppColors.fernGreen.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  )
                ]
              : [],
        ),
        child: TextFormField(
          controller: widget.ctrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          style: GoogleFonts.josefinSans(
            fontSize: 14,
            color: AppColors.charcoal,
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Enter your email';
            if (!v.contains('@') || !v.contains('.'))
              return 'Enter a valid email';
            return null;
          },
          decoration: InputDecoration(
            hintText: 'your@email.com',
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
              horizontal: 16,
              vertical: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatefulWidget {
  const _ContinueButton({required this.isLoading, required this.onTap});
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glow = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, __) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.fernGreen
                  .withValues(alpha: 0.2 + 0.12 * _glow.value),
              blurRadius: 10 + 6 * _glow.value,
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: widget.isLoading ? null : widget.onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.charcoal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Continue with email',
                  style: GoogleFonts.josefinSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
        ),
      ),
    );
  }
}

// Google button is a pure StatelessWidget — no animation controller
// this prevents jitter caused by the old StatefulWidget conflicting
// with parent rebuild cycles
class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.isLoading, required this.onTap});
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedOpacity(
        opacity: isLoading ? 0.55 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const _GoogleG(),
              const SizedBox(width: 12),
              Text(
                'Continue with Google',
                style: GoogleFonts.josefinSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// draws the actual Google G logo using canvas
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    final baseRect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      baseRect,
      -0.75,
      1.6,
      false,
      paint..color = const Color(0xFF4285F4),
    );

    canvas.drawArc(
      baseRect,
      0.85,
      1.2,
      false,
      paint..color = const Color(0xFFEA4335),
    );

    canvas.drawArc(
      baseRect,
      2.05,
      1.1,
      false,
      paint..color = const Color(0xFFFBBC05),
    );

    canvas.drawArc(
      baseRect,
      3.15,
      1.2,
      false,
      paint..color = const Color(0xFF34A853),
    );

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + r * 0.85, cy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// animated logo

class _AnimatedLogo extends StatelessWidget {
  const _AnimatedLogo({required this.ctrl});
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        return SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // two pulsing echo rings
              ...List.generate(2, (i) {
                final phase = (ctrl.value + i * 0.4) % 1.0;
                return Opacity(
                  opacity: (1 - phase) * 0.18,
                  child: Transform.scale(
                    scale: 1.0 + phase * 0.65,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.fernGreen,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── typewriter text ─────────────────────────────────────────────────────────

class _TypewriterText extends StatefulWidget {
  const _TypewriterText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  int _chars = 0;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.text.length * 60),
    );
    _c.addListener(() {
      final n = (_c.value * widget.text.length).round();
      if (n != _chars) setState(() => _chars = n);
    });
    Future.delayed(
      const Duration(milliseconds: 400),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.text.substring(0, _chars.clamp(0, widget.text.length)),
          style: widget.style,
        ),
        if (_chars < widget.text.length)
          Container(width: 2, height: 30, color: AppColors.fernGreen),
      ],
    );
  }
}

// ─── animated dot ────────────────────────────────────────────────────────────

class _Dot extends StatefulWidget {
  const _Dot({required this.delay});
  final double delay;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeInOut),
    );
    Future.delayed(
      Duration(milliseconds: (widget.delay * 1000).toInt()),
      () {
        if (mounted) _c.repeat(reverse: true);
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 5,
        height: 5,
        decoration: const BoxDecoration(
          color: AppColors.fernGreen,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── particle ────────────────────────────────────────────────────────────────

class _Particle {
  final double startX, startY, size, offset, amplitude;
  final Color color;

  const _Particle({
    required this.startX,
    required this.startY,
    required this.size,
    required this.offset,
    required this.amplitude,
    required this.color,
  });

  factory _Particle.random(math.Random rng) {
    const colors = [
      Color(0xFF4CAF6E),
      Color(0xFF81C784),
      Color(0xFFA5D6A7),
    ];
    return _Particle(
      startX: rng.nextDouble(),
      startY: rng.nextDouble(),
      size: 4 + rng.nextDouble() * 7,
      offset: rng.nextDouble(),
      amplitude: 0.4 + rng.nextDouble() * 0.6,
      color: colors[rng.nextInt(colors.length)],
    );
  }
}
