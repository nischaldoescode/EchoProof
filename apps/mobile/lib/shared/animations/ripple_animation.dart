// ripple animation widget
// shows expanding concentric circles — used on pending/awaiting echoes
// matches the echo wave brand motif

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';

class RippleAnimation extends StatefulWidget {
  const RippleAnimation({
    super.key,
    this.color = AppColors.fernGreen,
    this.size = 48.0,
    this.ringCount = 3,
  });

  final Color  color;
  final double size;
  final int    ringCount;

  @override
  State<RippleAnimation> createState() => _RippleAnimationState();
}

class _RippleAnimationState extends State<RippleAnimation>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
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
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RipplePainter(
              progress: _controller.value,
              color: widget.color,
              ringCount: widget.ringCount,
            ),
          );
        },
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  const _RipplePainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  final double progress;
  final Color  color;
  final int    ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    for (int i = 0; i < ringCount; i++) {
      final ringProgress = ((progress + i / ringCount) % 1.0);
      final radius  = maxRadius * ringProgress;
      final opacity = (1.0 - ringProgress) * 0.5;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    // center dot
    canvas.drawCircle(
      center, 3,
      Paint()
        ..color = color.withValues(alpha: 0.7)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) =>
      old.progress != progress;
}