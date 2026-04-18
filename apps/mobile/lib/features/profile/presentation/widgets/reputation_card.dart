// reputation card — shown at the top of the profile screen
// displays trust tier, score, bond stats, and on-chain identity status

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../shared/widgets/trust_tier_label.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../providers/profile_provider.dart';

class ReputationCard extends StatelessWidget {
  const ReputationCard({super.key, required this.profile});
  final ProfileState profile;

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
          Row(
            children: [
              // avatar
              CircleAvatar(
                radius: AppSpacing.avatarSizeMd / 2,
                backgroundColor: AppColors.softSand,
                backgroundImage: profile.avatarUrl != null
                    ? NetworkImage(profile.avatarUrl!)
                    : null,
                child: profile.avatarUrl == null
                    ? const Icon(Icons.person_outline,
                        size: 22, color: AppColors.textTertiary)
                    : null,
              ),

              const SizedBox(width: AppSpacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '@${profile.username}',
                          style: AppTypography.textTheme.titleMedium,
                        ),
                        if (profile.isIdentityVerified) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    TrustTierLabel(tier: profile.trustTier),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // stats row
          Row(
            children: [
              _Stat(label: 'Echoes',  value: profile.echoCount),
              _Divider(),
              _Stat(label: 'Proofs',  value: profile.proofCount),
              _Divider(),
              _Stat(label: 'Score',   value: profile.trustScore),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),

          // bonds row
          Row(
            children: [
              _BondStat(label: 'Settled',   value: profile.settledBonds,   color: AppColors.fernGreen),
              const SizedBox(width: AppSpacing.md),
              _BondStat(label: 'Active',    value: profile.activeBonds,    color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.md),
              _BondStat(label: 'Contested', value: profile.contestedBonds, color: AppColors.sunsetCoral),
            ],
          ),

          if (profile.walletAddress != null) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(Icons.circle, size: 6, color: AppColors.fernGreen),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Reputation anchored',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.fernGreenDark,
                    fontFamily: AppTypography.fontFamily,
                    fontWeight: FontWeight.w500,
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
  final int    value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: AppTypography.textTheme.headlineSmall,
          ),
          Text(label, style: AppTypography.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _BondStat extends StatelessWidget {
  const _BondStat({required this.label, required this.value, required this.color});
  final String label;
  final int    value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 24,
      color: AppColors.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}