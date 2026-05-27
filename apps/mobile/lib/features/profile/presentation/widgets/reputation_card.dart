// reputation card
// displays user trust stats on the profile screen
// takes plain parameters — no dependency on ProfileState

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../shared/widgets/trust_tier_label.dart';
import '../../../../shared/widgets/verified_badge.dart';

class ReputationCard extends StatelessWidget {
  const ReputationCard({
    super.key,
    required this.username,
    required this.trustTier,
    required this.trustScore,
    required this.echoCount,
    required this.proofCount,
    required this.isIdentityVerified,
    required this.settledBonds,
    required this.contestedBonds,
    required this.activeBonds,
    this.avatarUrl,
    this.walletAddress,
  });

  final String username;
  final String trustTier;
  final int trustScore;
  final int echoCount;
  final int proofCount;
  final bool isIdentityVerified;
  final int settledBonds;
  final int contestedBonds;
  final int activeBonds;
  final String? avatarUrl;
  final String? walletAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // avatar + username row
          Row(
            children: [
              CircleAvatar(
                radius: AppSpacing.avatarSizeMd / 2,
                backgroundColor: AppColors.softSand,
                backgroundImage: avatarImageProvider(avatarUrl),
                child: avatarImageProvider(avatarUrl) == null
                    ? const Icon(
                        Icons.person_outline,
                        size: 22,
                        color: AppColors.textTertiary,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '@$username',
                            style: AppTypography.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isIdentityVerified) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    TrustTierLabel(tier: trustTier),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // stats row
          Row(
            children: [
              _Stat(label: context.l('Echoes'), value: echoCount),
              _VerticalDivider(),
              _Stat(label: context.l('Proofs'), value: proofCount),
              _VerticalDivider(),
              _Stat(label: context.l('Score'), value: trustScore),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // bond stats
          Row(
            children: [
              _BondStat(
                label: context.l('Settled'),
                value: settledBonds,
                color: AppColors.fernGreen,
              ),
              const SizedBox(width: AppSpacing.md),
              _BondStat(
                label: context.l('Active'),
                value: activeBonds,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.md),
              _BondStat(
                label: context.l('Contested'),
                value: contestedBonds,
                color: AppColors.sunsetCoral,
              ),
            ],
          ),

          // wallet address if connected
          if (walletAddress != null) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(
                  Icons.link_outlined,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${walletAddress!.substring(0, 6)}...${walletAddress!.substring(walletAddress!.length - 6)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                    fontFamily: AppTypography.fontFamily,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: AppTypography.textTheme.headlineSmall),
          Text(label, style: AppTypography.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _BondStat extends StatelessWidget {
  const _BondStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
            fontFamily: AppTypography.fontFamily,
          ),
        ),
      ],
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: AppColors.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}
