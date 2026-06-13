// shimmer loading widgets
// used while feed/profile data is loading
// matches echo card dimensions exactly so layout doesn't shift on load

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';

/// shimmer placeholder matching the echo card shape
class EchoCardShimmer extends StatelessWidget {
  const EchoCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.softSand,
      highlightColor: AppColors.white,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.softSand,
          borderRadius: BorderRadius.circular(AppSpacing.echoCardRadius),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header row
              Row(
                children: [
                  _ShimmerBox(width: 36, height: 36, radius: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerBox(width: 100, height: 12),
                      const SizedBox(height: 4),
                      _ShimmerBox(width: 60, height: 10),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _ShimmerBox(width: double.infinity, height: 14),
              const SizedBox(height: AppSpacing.sm),
              _ShimmerBox(width: double.infinity, height: 12),
              const SizedBox(height: AppSpacing.xs),
              _ShimmerBox(width: 180, height: 12),
              const Spacer(),
              _ShimmerBox(width: double.infinity, height: 5, radius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    this.radius = 6,
  });
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class EchoLogoLoader extends StatefulWidget {
  const EchoLogoLoader({super.key, this.size = 74, this.label});

  final double size;
  final String? label;

  @override
  State<EchoLogoLoader> createState() => _EchoLogoLoaderState();
}

class _EchoLogoLoaderState extends State<EchoLogoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = _controller.value;

              return SizedBox(
                width: widget.size * 1.35,
                height: widget.size * 0.74,
                child: CustomPaint(
                  painter: _SignalFlowLoaderPainter(progress: value),
                ),
              );
            },
          ),
          if (widget.label != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              widget.label!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalFlowLoaderPainter extends CustomPainter {
  const _SignalFlowLoaderPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final railPaint = Paint()
      ..color = AppColors.fernGreen.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final pulsePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.fernGreen.withValues(alpha: 0),
          AppColors.fernGreen.withValues(alpha: 0.85),
          AppColors.fernGreenDark.withValues(alpha: 0.72),
          AppColors.fernGreen.withValues(alpha: 0),
        ],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()
      ..color = AppColors.fernGreenDark.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 3; i++) {
      final inset = i * size.height * 0.13;
      final rect = Rect.fromCenter(
        center: center,
        width: size.width - inset * 2,
        height: size.height - inset * 1.3,
      );
      final start = -2.85 + i * 0.18;
      final sweep = 1.22 + i * 0.08;
      canvas.drawArc(rect, start, sweep, false, railPaint);
      canvas.drawArc(
        rect,
        start + progress * 6.28318530718,
        sweep * 0.54,
        false,
        pulsePaint,
      );
    }

    final dotX = (size.width * (0.18 + progress * 0.64)).clamp(
      size.width * 0.18,
      size.width * 0.82,
    );
    final dotY = center.dy + (progress - 0.5).abs() * size.height * 0.18;
    canvas.drawCircle(Offset(dotX.toDouble(), dotY), 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SignalFlowLoaderPainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}
