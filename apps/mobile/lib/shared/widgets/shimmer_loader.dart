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
  const _ShimmerBox({required this.width, required this.height, this.radius = 6});
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