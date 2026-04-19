// login screen
// email + password + google oauth
// 3d perspective tilt on form card
// uses AuthService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {

  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey            = GlobalKey<FormState>();

  late final AnimationController _cardController;
  late final Animation<double>   _cardEntranceY;
  late final Animation<double>   _cardFade;

  bool _obscurePassword = true;
  bool _isSignUp        = false;

  @override
  void initState() {
    super.initState();
    _cardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _cardEntranceY = Tween<double>(begin: 60, end: 0).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );
    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _cardController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    _cardController.forward();
  }

  @override
  void dispose() {
    _cardController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthService>();
    if (_isSignUp) {
      await auth.signUpWithEmail(
        email:    _emailController.text.trim(),
        password: _passwordController.text,
      );
    } else {
      await auth.signInWithEmail(
        email:    _emailController.text.trim(),
        password: _passwordController.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.sizeOf(context);
    final isWide = size.width > 600;
    final auth  = context.watch<AuthService>();

    // navigate when login succeeds
    if (auth.isLoggedIn && !auth.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/onboarding');
      });
    }

    // show error snackbar
    if (auth.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:          Text(auth.error!),
              backgroundColor:  AppColors.sunsetCoral,
              behavior:         SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          context.read<AuthService>().clearError();
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.charcoal,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? size.width * 0.2 : AppSpacing.xl,
              vertical:   AppSpacing.xl,
            ),
            child: AnimatedBuilder(
              animation: _cardController,
              builder: (context, child) {
                return Opacity(
                  opacity: _cardFade.value,
                  child: Transform.translate(
                    offset: Offset(0, _cardEntranceY.value),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  // 3d tilt logo
                  _TiltCard(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  Text(
                    'Echoproof',
                    style: AppTypography.textTheme.headlineMedium?.copyWith(
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'truth, verified by community',
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxxl),

                  // 3d tilt form card
                  _TiltCard(
                    tiltStrength: 0.03,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _AuthTabRow(
                              isSignUp: _isSignUp,
                              onToggle: (val) =>
                                  setState(() => _isSignUp = val),
                            ),

                            const SizedBox(height: AppSpacing.xl),

                            TextFormField(
                              controller:  _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                hintText:   'email address',
                                prefixIcon: Icon(
                                  Icons.alternate_email,
                                  size: 18,
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'email is required';
                                }
                                if (!v.contains('@')) {
                                  return 'enter a valid email';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: AppSpacing.md),

                            TextFormField(
                              controller:  _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText:   'password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 18,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 18,
                                    color: AppColors.textTertiary,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'password is required';
                                }
                                if (_isSignUp && v.length < 8) {
                                  return 'minimum 8 characters';
                                }
                                return null;
                              },
                            ),

                            const SizedBox(height: AppSpacing.xl),

                            SizedBox(
                              width: double.infinity,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: auth.isLoading
                                    ? const Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.charcoal,
                                          ),
                                        ),
                                      )
                                    : ElevatedButton(
                                        onPressed: _submit,
                                        child: Text(
                                          _isSignUp
                                              ? 'Create account'
                                              : 'Sign in',
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: AppSpacing.lg),

                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    'or',
                                    style: AppTypography.textTheme.labelMedium,
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.lg),

                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    context.read<AuthService>().signInWithGoogle(),
                                icon:  const _GoogleIcon(),
                                label: const Text('Continue with Google'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.charcoal,
                                  side: const BorderSide(
                                    color: AppColors.borderMedium,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppSpacing.radiusMd,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
    );
  }
}

// interactive 3d tilt card — responds to touch drag
class _TiltCard extends StatefulWidget {
  const _TiltCard({required this.child, this.tiltStrength = 0.06});
  final Widget child;
  final double tiltStrength;

  @override
  State<_TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<_TiltCard> {
  double _rotX = 0;
  double _rotY = 0;

  void _onPanUpdate(DragUpdateDetails d) {
    final size = context.size ?? const Size(300, 300);
    setState(() {
      _rotY += d.delta.dx / size.width  * widget.tiltStrength * math.pi;
      _rotX -= d.delta.dy / size.height * widget.tiltStrength * math.pi;
      _rotX = _rotX.clamp(-0.3, 0.3);
      _rotY = _rotY.clamp(-0.3, 0.3);
    });
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _rotX = 0;
      _rotY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd:    _onPanEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_rotX)
          ..rotateY(_rotY),
        transformAlignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

class _AuthTabRow extends StatelessWidget {
  const _AuthTabRow({required this.isSignUp, required this.onToggle});
  final bool             isSignUp;
  final void Function(bool) onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Tab(
          label:  'Sign in',
          active: !isSignUp,
          onTap:  () => onToggle(false),
        ),
        const SizedBox(width: AppSpacing.md),
        _Tab(
          label:  'Create account',
          active: isSignUp,
          onTap:  () => onToggle(true),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String   label;
  final bool     active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.charcoal : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:   14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color:      active ? AppColors.charcoal : AppColors.textTertiary,
            fontFamily: AppTypography.fontFamily,
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;

    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];

    final starts = [
      -math.pi * 0.25,
       math.pi * 0.25,
       math.pi * 0.75,
       math.pi * 1.25,
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r - 1),
        starts[i],
        math.pi * 0.5,
        false,
        Paint()
          ..color       = colors[i]
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}