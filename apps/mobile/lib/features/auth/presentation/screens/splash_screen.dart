// splash screen
// two-phase animation:
//   phase 1 (native): flutter_native_splash shows static logo instantly on app launch
//   phase 2 (this file): smooth animated transition into the app
//
// the logo png has a gradient background — we match the scaffold color to it
// so the transition from native splash to this screen is invisible

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {

  // phase 1: logo fades and scales in (0 - 600ms)
  late final AnimationController _logoController;
  late final Animation<double>   _logoScale;
  late final Animation<double>   _logoOpacity;

  // phase 2: echo wave rings pulse out from logo (400 - 1200ms)
  late final AnimationController _ringsController;
  late final Animation<double>   _ringsOpacity;

  // phase 3: fern green glow on the checkmark (1200 - 1600ms)
  late final AnimationController _glowController;
  late final Animation<double>   _glowOpacity;

  // phase 4: whole screen fades to white before navigating (1800 - 2200ms)
  late final AnimationController _exitController;
  late final Animation<double>   _exitFade;

  // background interpolates from logo gradient color to white on exit
  // this creates a seamless transition to the login or feed screen
  late final Animation<Color?>   _bgColor;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController,
          curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );

    _ringsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _ringsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ringsController,
          curve: const Interval(0, 0.3, curve: Curves.easeIn)),
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _glowOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeIn),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _exitFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _exitController, curve: Curves.easeIn),
    );
    _bgColor = ColorTween(
      // matches the logo's bottom-right corner gradient color approximately
      begin: const Color(0xFFE8F5EE),
      end:   Colors.white,
    ).animate(_exitController);

    _runSequence();
    _scheduleNavigation();
  }

  Future<void> _runSequence() async {
    // slight delay so the native splash transition settles
    await Future.delayed(const Duration(milliseconds: 100));
    await _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    _ringsController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    await _glowController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) await _exitController.forward();
  }

  void _scheduleNavigation() {
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      final authState = ref.read(authStateProvider);
      authState.when(
        data:    (user) => context.go(user != null ? '/feed' : '/login'),
        loading: ()     => context.go('/login'),
        error:   (_, __) => context.go('/login'),
      );
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
    final size = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _logoController,
        _ringsController,
        _glowController,
        _exitController,
      ]),
      builder: (context, _) {
        // background: starts as a very light fern green (matches logo gradient)
        // exits to pure white — seamless transition to next screen
        final bg = _bgColor.value ?? const Color(0xFFE8F5EE);

        return Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              // exit fade overlay — white layer that covers everything on exit
              if (_exitController.value > 0)
                Positioned.fill(
                  child: Opacity(
                    opacity: _exitFade.value,
                    child: const ColoredBox(color: Colors.white),
                  ),
                ),

              // centered content
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // echo wave rings — pulse out from behind logo
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // three expanding rings
                          ...List.generate(3, (i) {
                            final ringAnim = Tween<double>(begin: 0, end: 1).animate(
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
                              opacity: _ringsOpacity.value * (1 - ringAnim.value) * 0.35,
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

                          // the actual logo
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

                    // app name fades in with logo
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

// the logo widget
// clips your png into a rounded square and adds a subtle green glow
// on the verification checkmark area when glowOpacity > 0
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
          // subtle shadow matching the logo gradient
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF6E).withOpacity(0.25 * glowOpacity),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),

          // the actual logo png — clipped to rounded square
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