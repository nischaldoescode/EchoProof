import 'package:flutter/material.dart';
import '../../app/theme/colors.dart';

enum BadgeType { none, verified, pro, verifiedPro }

BadgeType resolveBadgeType({
  required bool isVerified,
  required bool isPro,
}) {
  if (isVerified && isPro) return BadgeType.verifiedPro;
  if (isVerified) return BadgeType.verified;
  if (isPro) return BadgeType.pro;
  return BadgeType.none;
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Verified ring
        if (badgeType != BadgeType.none)
          Container(
            width: radius * 2 + 4,
            height: radius * 2 + 4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: badgeType == BadgeType.verifiedPro
                    ? [const Color(0xFF1DA1F2), const Color(0xFF0D47A1)]
                    : [AppColors.fernGreen, AppColors.fernGreenDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        Positioned(
          left: badgeType != BadgeType.none ? 2 : 0,
          top: badgeType != BadgeType.none ? 2 : 0,
          child: CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.softSand,
            backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                ? NetworkImage(avatarUrl!)
                : null,
            child: (avatarUrl == null || avatarUrl!.isEmpty)
                ? Icon(Icons.person_outline,
                    size: radius * 0.7, color: AppColors.textTertiary)
                : null,
          ),
        ),
        // Badge dot
        if (badgeType != BadgeType.none)
          Positioned(
            right: 0,
            bottom: 0,
            child: _AnimatedBadgeDot(type: badgeType),
          ),
      ],
    );
  }
}

class _AnimatedBadgeDot extends StatefulWidget {
  const _AnimatedBadgeDot({required this.type});
  final BadgeType type;

  @override
  State<_AnimatedBadgeDot> createState() => _AnimatedBadgeDotState();
}

class _AnimatedBadgeDotState extends State<_AnimatedBadgeDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color badgeColor;
    final IconData badgeIcon;
    switch (widget.type) {
      case BadgeType.verifiedPro:
        badgeColor = const Color(0xFF1DA1F2); // blue
        badgeIcon = Icons.star_rounded;
      case BadgeType.pro:
        badgeColor = const Color(0xFFFFB300); // amber gold
        badgeIcon = Icons.star_rounded;
      case BadgeType.verified:
        badgeColor = AppColors.fernGreen;
        badgeIcon = Icons.verified_rounded;
      case BadgeType.none:
        badgeColor = Colors.transparent;
        badgeIcon = Icons.circle;
    }

    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: badgeColor,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(badgeIcon, size: 8, color: Colors.white),
      ),
    );
  }
}
