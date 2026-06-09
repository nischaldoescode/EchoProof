// splash screen
// two-phase animation: native splash (instant) then this animated screen
// uses authservice and onboardingservice via provider no riverpod

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../../../onboarding/presentation/services/onboarding_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;

  late final AnimationController _ringsController;
  late final Animation<double> _ringsOpacity;

  late final AnimationController _glowController;

  late final AnimationController _exitController;
  late final Animation<double> _exitFade;
  late final Animation<Color?> _bgColor;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _runSequence();
    _scheduleNavigation();
  }

  void _initAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );

    _ringsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _ringsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ringsController,
        curve: const Interval(0, 0.3, curve: Curves.easeIn),
      ),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _exitFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );
    _bgColor = ColorTween(
      begin: const Color(0xFFE8F5EE),
      end: Colors.white,
    ).animate(_exitController);
  }

  Future<void> _runSequence() async {
    if (!await _waitWhileMounted(const Duration(milliseconds: 100))) return;
    await _logoController.forward();
    if (!await _waitWhileMounted(const Duration(milliseconds: 100))) return;
    _ringsController.forward();
    if (!await _waitWhileMounted(const Duration(milliseconds: 600))) return;
    await _glowController.forward();
    if (!await _waitWhileMounted(const Duration(milliseconds: 400))) return;
    await _exitController.forward();
  }

  Future<bool> _waitWhileMounted(Duration duration) async {
    await Future.delayed(duration);
    return mounted;
  }

  void _scheduleNavigation() {
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final onboarding = context.read<OnboardingService>();

      if (auth.isLoggedIn) {
        if (onboarding.isComplete()) {
          context.go('/feed');
        } else {
          context.go('/onboarding');
        }
      } else {
        context.go('/login');
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _ringsController.dispose();
    _glowController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _logoController,
        _ringsController,
        _glowController,
        _exitController,
      ]),
      builder: (context, _) {
        final bg = _bgColor.value ?? const Color(0xFFE8F5EE);

        return Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              // white overlay fades in as screen exits
              if (_exitController.value > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: _exitFade.value,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),

              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // echo wave rings pulsing out from logo
                          ...List.generate(3, (i) {
                            final ringAnim =
                                Tween<double>(begin: 0, end: 1).animate(
                              CurvedAnimation(
                                parent: _ringsController,
                                curve: Interval(
                                  i * 0.15,
                                  0.6 + i * 0.15,
                                  curve: Curves.easeOut,
                                ),
                              ),
                            );
                            return Opacity(
                              opacity: _ringsOpacity.value *
                                  (1 - ringAnim.value) *
                                  0.35,
                              child: Transform.scale(
                                scale: 0.55 + ringAnim.value * 0.8,
                                child: Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF4CAF6E),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),

                          // logo mark with glow
                          Opacity(
                            opacity: _logoOpacity.value,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: _LogoMark(
                                glowOpacity: _glowController.value,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, (1 - _logoOpacity.value) * 8),
                        child: const Text(
                          'Echoproof',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Opacity(
                      opacity: _logoOpacity.value * 0.7,
                      child: const Text(
                        'truth, verified',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF5A5A5A),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark({required this.glowOpacity});
  final double glowOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // green glow that fades in at end of animation
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF6E)
                      .withValues(alpha: glowOpacity * 0.25),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),

          // your logo png clipped to rounded square
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Image.asset(
              'assets/images/logo.png',
              width: 110,
              height: 110,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }
}
