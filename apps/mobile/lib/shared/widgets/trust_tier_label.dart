// trust tier label widget — full text version (for profiles)
// compact version is TrustBadge in echo/presentation/widgets

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/typography.dart';
import '../../features/echo/domain/entities/echo_entity.dart';

class TrustTierLabel extends StatelessWidget {
  const TrustTierLabel({super.key, required this.tier});
  final String tier;

  @override
  Widget build(BuildContext context) {
    final trustTier = TrustTier.fromString(tier);

    final (label, textColor, bgColor) = switch (trustTier) {
      TrustTier.elite      => ('Elite',      AppColors.fernGreenDark, AppColors.fernGreenLight),
      TrustTier.high       => ('High trust', AppColors.fernGreenDark, AppColors.fernGreenLight),
      TrustTier.medium     => ('Medium trust', AppColors.textSecondary, AppColors.softSand),
      TrustTier.low        => ('Low trust',  AppColors.textTertiary, AppColors.softSand),
      TrustTier.unverified => ('Unverified', AppColors.textTertiary, AppColors.softSand),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
          fontFamily: AppTypography.fontFamily,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}