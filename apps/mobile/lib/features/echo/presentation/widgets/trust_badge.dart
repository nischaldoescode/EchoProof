// trust tier badge widget
// shown on echo cards and user profiles
// subtle, not flashy green for verified tiers, neutral for unverified

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';

class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final trustTier = TrustTier.fromString(tier);
    final (label, textColor, bgColor) = _style(trustTier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: textColor,
          fontFamily: AppTypography.fontFamily,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  (String, Color, Color) _style(TrustTier tier) {
    return switch (tier) {
      TrustTier.elite => (
          'Elite',
          AppColors.fernGreenDark,
          AppColors.fernGreenLight
        ),
      TrustTier.high => (
          'High',
          AppColors.fernGreenDark,
          AppColors.fernGreenLight
        ),
      TrustTier.medium => (
          'Medium',
          AppColors.textSecondary,
          AppColors.softSand
        ),
      TrustTier.low => ('Low', AppColors.textTertiary, AppColors.softSand),
      TrustTier.unverified => (
          'Unverified',
          AppColors.textTertiary,
          AppColors.softSand
        ),
    };
  }
}
