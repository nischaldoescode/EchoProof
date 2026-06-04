// animated confidence bar widget
// shows the % of weighted community support for an echo
// animates smoothly when confidence value changes

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_status.dart';

class ConfidenceBar extends StatelessWidget {
  const ConfidenceBar({
    super.key,
    required this.confidence,
    required this.status,
  });

  /// 0.0 to 100.0
  final double confidence;
  final EchoStatus status;

  @override
  Widget build(BuildContext context) {
    final fraction = (confidence / 100.0).clamp(0.0, 1.0);
    final barColor = _barColor(status);
    final label = _label(confidence, status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.textTheme.labelMedium,
            ),
            Text(
              confidence > 0 ? '${confidence.toStringAsFixed(0)}%' : '',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: barColor,
                fontFamily: AppTypography.fontFamily,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.confidenceBarHeight),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, value, _) {
              return LinearProgressIndicator(
                value: value,
                minHeight: AppSpacing.confidenceBarHeight,
                backgroundColor: AppColors.borderSubtle,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _barColor(EchoStatus status) {
    return switch (status) {
      EchoStatus.verified => AppColors.fernGreen,
      EchoStatus.disputed => AppColors.sunsetCoral,
      EchoStatus.controversial => AppColors.statusControversial,
      EchoStatus.underReview => AppColors.statusUnderReview,
      _ => AppColors.textTertiary,
    };
  }

  String _label(double confidence, EchoStatus status) {
    if (confidence == 0) return 'awaiting signals';
    return switch (status) {
      EchoStatus.verified => 'community confidence',
      EchoStatus.disputed => 'community confidence',
      EchoStatus.controversial => 'community split',
      _ => 'community confidence',
    };
  }
}
