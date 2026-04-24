// echo card widget
// the main content unit shown in the feed
// plain StatelessWidget — no riverpod

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import 'confidence_bar.dart';
import 'trust_badge.dart';
import 'interaction_buttons.dart';

class EchoCard extends StatelessWidget {
  const EchoCard({
    super.key,
    required this.echo,
    this.onTap,
  });

  final EchoEntity echo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppSpacing.echoCardRadius),
          border: Border.all(
            color: _borderColor(echo.status),
            width: echo.status == EchoStatus.controversial ? 1.5 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(echo: echo),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (echo.title.isNotEmpty) ...[
                    Text(
                      echo.title,
                      style: AppTypography.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    echo.content,
                    style: AppTypography.textTheme.bodyMedium,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (echo.status != EchoStatus.active &&
                echo.status != EchoStatus.pendingVerification)
              _StatusLabel(status: echo.status),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: ConfidenceBar(
                confidence: echo.confidenceScore,
                status: echo.status,
              ),
            ),
            const Divider(
              height: 1,
              indent: AppSpacing.lg,
              endIndent: AppSpacing.lg,
            ),
            InteractionButtons(echo: echo),
          ],
        ),
      ),
    );
  }

  Color _borderColor(EchoStatus status) {
    return switch (status) {
      EchoStatus.verified => AppColors.fernGreen.withValues(alpha: 0.4),
      EchoStatus.disputed => AppColors.sunsetCoral.withValues(alpha: 0.4),
      EchoStatus.controversial =>
        AppColors.statusControversial.withValues(alpha: 0.4),
      EchoStatus.underReview => AppColors.statusUnderReview.withValues(alpha: 0.3),
      EchoStatus.hidden => AppColors.borderSubtle,
      _ => AppColors.borderSubtle,
    };
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          _AvatarWithRing(
            avatarUrl: echo.userAvatarUrl,
            isVerified: echo.userIsVerified,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  echo.username,
                  style: AppTypography.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  echo.category.displayName,
                  style: AppTypography.textTheme.labelMedium,
                ),
              ],
            ),
          ),
          TrustBadge(tier: echo.userTrustTier),
          const SizedBox(width: AppSpacing.sm),
          Text(echo.timeAgo, style: AppTypography.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _AvatarWithRing extends StatelessWidget {
  const _AvatarWithRing({required this.avatarUrl, required this.isVerified});
  final String? avatarUrl;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.avatarSizeSm + 4,
      height: AppSpacing.avatarSizeSm + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isVerified ? AppColors.fernGreen : AppColors.borderSubtle,
          width: isVerified ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
          radius: AppSpacing.avatarSizeSm / 2,
          backgroundColor: AppColors.softSand,
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null
              ? const Icon(
                  Icons.person_outline,
                  size: 18,
                  color: AppColors.textTertiary,
                )
              : null,
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});
  final EchoStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      EchoStatus.verified => (
          'Verified by community',
          AppColors.fernGreenDark,
          AppColors.fernGreenLight,
        ),
      EchoStatus.disputed => (
          'Disputed',
          AppColors.sunsetCoralDark,
          AppColors.sunsetCoralLight,
        ),
      EchoStatus.controversial => (
          'Controversial — community split',
          const Color(0xFF7A5200),
          const Color(0xFFFFF3E0),
        ),
      EchoStatus.underReview => (
          'Under community review',
          const Color(0xFF7A5200),
          const Color(0xFFFFF8E1),
        ),
      EchoStatus.rejected => (
          'Rejected',
          AppColors.sunsetCoralDark,
          AppColors.sunsetCoralLight,
        ),
      _ => (
          'Awaiting echoes...',
          AppColors.textTertiary,
          AppColors.softSand,
        ),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
          fontFamily: AppTypography.fontFamily,
        ),
      ),
    );
  }
}
