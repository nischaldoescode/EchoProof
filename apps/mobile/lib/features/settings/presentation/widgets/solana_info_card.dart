import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';

class SolanaInfoCard extends StatelessWidget {
  const SolanaInfoCard({super.key});

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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.fernGreenLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.link_outlined,
                  size: 18,
                  color: AppColors.fernGreen,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                'Solana record layer',
                style: AppTypography.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _InfoRow(
            icon: Icons.verified_outlined,
            title: 'Echoes are anchored on Solana',
            description:
                'New posts and verified echoes create Solana memo records with a fingerprint of the content, confidence score, and timestamp.',
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.workspace_premium_outlined,
            title: 'Portable reputation',
            description:
                'High-trust actions can be connected to public Solana records, so credibility is easier to verify outside the app.',
          ),
          const SizedBox(height: AppSpacing.md),
          _InfoRow(
            icon: Icons.handshake_outlined,
            title: 'Truth Bonds',
            description:
                'Bonding your reputation to a verified echo creates a Solana record and a 30-day settlement window.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.fernGreenLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 13,
                  color: AppColors.fernGreenDark,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Records are written through Solana Memo Program transactions. Echoproof can show their status, but cannot rewrite an anchored transaction.',
                    style: GoogleFonts.josefinSans(
                      fontSize: 11,
                      color: AppColors.fernGreenDark,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.fernGreen),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
