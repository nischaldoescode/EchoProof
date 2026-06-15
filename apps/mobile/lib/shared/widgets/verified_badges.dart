// verified badges
// @params none

import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';
import 'safe_circle_avatar.dart';

enum BadgeType { none, verified, pro, verifiedPro }

BadgeType resolveBadgeType({required bool isVerified, required bool isPro}) {
  if (isVerified && isPro) return BadgeType.verifiedPro;
  if (isPro) return BadgeType.pro;
  if (isVerified) return BadgeType.verified;
  return BadgeType.none;
}

class AccountVerifiedBadge extends StatelessWidget {
  const AccountVerifiedBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'verified account',
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: AppColors.fernGreen,
      ),
    );
  }
}

class AvatarWithBadge extends StatelessWidget {
  const AvatarWithBadge({
    super.key,
    required this.avatarUrl,
    required this.radius,
    required this.badgeType,
  });

  final String? avatarUrl;
  final double radius;
  final BadgeType badgeType;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;

    return SizedBox(
      width: size,
      height: size,
      child: SafeCircleAvatar(
        radius: radius,
        backgroundColor: AppColors.softSand,
        avatarUrl: avatarUrl,
      ),
    );
  }
}
