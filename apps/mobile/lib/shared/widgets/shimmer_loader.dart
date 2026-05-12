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
  const _ShimmerBox(
      {required this.width, required this.height, this.radius = 6});
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
  const EchoLogoLoader({
    super.key,
    this.size = 74,
    this.label,
  });

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
              final glow = 0.16 + (value < 0.5 ? value : 1 - value) * 0.28;

              return Transform.scale(
                scale: 0.96 + glow * 0.12,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.fernGreen.withValues(alpha: glow),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: FractionalTranslation(
                            translation: Offset(-1.4 + value * 2.8, 0),
                            child: Container(
                              width: widget.size * 0.34,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.62),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
