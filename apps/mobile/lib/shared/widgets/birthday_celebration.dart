// birthday celebration
// @params none

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';

/// call this from main.dart after successful login to check birthday
/// pass the date_of_birth from users_public
void maybeTriggerBirthdayEaster(BuildContext context, String? dateOfBirth) {
  if (dateOfBirth == null) return;
  final dob = DateTime.tryParse(dateOfBirth);
  if (dob == null) return;
  final now = DateTime.now();
  if (dob.month == now.month && dob.day == now.day) {
    // small delay so the feed loads first
    Future.delayed(const Duration(milliseconds: 800), () {
      if (context.mounted) {
        showGeneralDialog(
          context: context,
          barrierDismissible: false,
          barrierLabel: 'birthday',
          barrierColor: Colors.black54,
          transitionDuration: const Duration(milliseconds: 500),
          transitionBuilder: (ctx, anim, _, child) {
            return ScaleTransition(
              scale: Tween<double>(begin: 0.7, end: 1).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
              ),
              child: FadeTransition(
                opacity: anim,
                child: child,
              ),
            );
          },
          pageBuilder: (ctx, _, __) => _BirthdayModal(age: now.year - dob.year),
        );
      }
    });
  }
}

class _BirthdayModal extends StatefulWidget {
  const _BirthdayModal({required this.age});
  final int age;

  @override
  State<_BirthdayModal> createState() => _BirthdayModalState();
}

class _BirthdayModalState extends State<_BirthdayModal>
    with TickerProviderStateMixin {
  late final AnimationController _confettiCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;
  final List<_ConfettiParticle> _particles = [];
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulse = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // generate confetti particles
    for (int i = 0; i < 60; i++) {
      _particles.add(_ConfettiParticle.random(_rng));
    }
  }

  @override
  void dispose() {
    _confettiCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // confetti layer
          AnimatedBuilder(
            animation: _confettiCtrl,
            builder: (_, __) => SizedBox(
              width: size.width - 48,
              height: 500,
              child: CustomPaint(
                painter: _ConfettiPainter(
                  particles: _particles,
                  progress: _confettiCtrl.value,
                ),
              ),
            ),
          ),

          // card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.fernGreen.withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // animated cake emoji
                ScaleTransition(
                  scale: _pulse,
                  child: Text(
                    '🎂',
                    style: const TextStyle(fontSize: 72),
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Happy Birthday!',
                  style: GoogleFonts.josefinSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 10),

                // echoproof-branded message
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: GoogleFonts.josefinSans(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                    children: [
                      const TextSpan(text: 'You\'re '),
                      TextSpan(
                        text: '${widget.age} ',
                        style: GoogleFonts.josefinSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.fernGreen,
                        ),
                      ),
                      const TextSpan(
                          text:
                              'echoes old today.\nMay your truth always resonate.'),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // echo rings brand motif
                _EchoRings(),

                const SizedBox(height: 28),

                // trust tier message
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.fernGreenLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Text('✨', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your trust score gets a birthday bonus today.',
                          style: GoogleFonts.josefinSans(
                            fontSize: 13,
                            color: AppColors.fernGreenDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.charcoal,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Thank you 🎉',
                      style: GoogleFonts.josefinSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// animated echo rings echoproof's brand motif as decoration
class _EchoRings extends StatefulWidget {
  @override
  State<_EchoRings> createState() => _EchoRingsState();
}

class _EchoRingsState extends State<_EchoRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _RingsPainter(progress: _ctrl.value),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 4; i++) {
      final p = ((progress + i * 0.25) % 1.0);
      final radius = 10 + p * 60;
      final opacity = (1 - p) * 0.6;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = AppColors.fernGreen.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    // center dot
    canvas.drawCircle(
      center,
      5,
      Paint()..color = AppColors.fernGreen.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.progress != progress;
}

class _ConfettiParticle {
  final double x; // 0-1 normalized
  final double startY; // 0-1 normalized start
  final double speedY;
  final double speedX;
  final double size;
  final Color color;
  final double rotation;
  final double rotationSpeed;
  final bool isCircle;

  const _ConfettiParticle({
    required this.x,
    required this.startY,
    required this.speedY,
    required this.speedX,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
    required this.isCircle,
  });

  factory _ConfettiParticle.random(math.Random rng) {
    const colors = [
      AppColors.fernGreen,
      Color(0xFFFFD700), // gold
      Color(0xFFFF6B6B), // coral
      Color(0xFF4ECDC4), // teal
      Color(0xFFFF9F43), // orange
      Color(0xFF54A0FF), // blue
    ];

    return _ConfettiParticle(
      x: rng.nextDouble(),
      startY: -0.1 - rng.nextDouble() * 0.3,
      speedY: 0.15 + rng.nextDouble() * 0.25,
      speedX: (rng.nextDouble() - 0.5) * 0.08,
      size: 4 + rng.nextDouble() * 8,
      color: colors[rng.nextInt(colors.length)],
      rotation: rng.nextDouble() * math.pi * 2,
      rotationSpeed: (rng.nextDouble() - 0.5) * 8,
      isCircle: rng.nextBool(),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter({
    required this.particles,
    required this.progress,
  });

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = (p.startY + progress * p.speedY) % 1.2;
      final x = p.x + progress * p.speedX;
      final opacity = progress < 0.7 ? 1.0 : (1.0 - (progress - 0.7) / 0.3);

      if (opacity <= 0) continue;

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity.clamp(0, 1));

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.rotation + progress * p.rotationSpeed);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.5,
          ),
          paint,
        );
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
