// top flow loader
// @params visible controls whether the moving rail is shown

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';

class TopFlowLoader extends StatefulWidget {
  const TopFlowLoader({super.key, required this.visible, this.height = 2.5});

  final bool visible;
  final double height;

  @override
  State<TopFlowLoader> createState() => _TopFlowLoaderState();
}

class _TopFlowLoaderState extends State<TopFlowLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.visible) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant TopFlowLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.visible && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: widget.visible ? 1 : 0,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _TopFlowPainter(progress: _controller.value),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopFlowPainter extends CustomPainter {
  const _TopFlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rail = Paint()
      ..color = AppColors.fernGreen.withValues(alpha: 0.08)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    final glow = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.fernGreen.withValues(alpha: 0),
          AppColors.fernGreen.withValues(alpha: 0.82),
          const Color(0xFF2E6FAE).withValues(alpha: 0.72),
          AppColors.fernGreen.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size)
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      rail,
    );

    final segment = size.width * 0.34;
    final start = -segment + (size.width + segment * 2) * progress;
    canvas.drawLine(
      Offset(start, size.height / 2),
      Offset(start + segment, size.height / 2),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _TopFlowPainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}
