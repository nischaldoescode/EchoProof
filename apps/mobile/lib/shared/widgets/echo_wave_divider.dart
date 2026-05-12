// echo wave divider
// a subtle animated wave line used as a section separator in feeds

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';

class EchoWaveDivider extends StatefulWidget {
  const EchoWaveDivider({super.key});

  @override
  State<EchoWaveDivider> createState() => _EchoWaveDividerState();
}

class _EchoWaveDividerState extends State<EchoWaveDivider>
    with SingleTickerProviderStateMixin {

  late final AnimationController _controller;
  late final Animation<double>   _phase;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _phase = Tween<double>(begin: 0, end: 1).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _phase,
      builder: (context, _) => CustomPaint(
        painter: _WavePainter(phase: _phase.value),
        size: const Size(double.infinity, 12),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const _WavePainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.borderSubtle
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final path = Path();
    const amplitude = 2.5;
    const wavelength = 40.0;

    path.moveTo(0, size.height / 2);

    for (double x = 0; x <= size.width; x++) {
      final y = size.height / 2 +
          amplitude * (0.5 * (1 + (x / wavelength + phase * 2 * 3.14159).remainder(3.14159).abs() * 2 - 1).sign);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.phase != phase;
}