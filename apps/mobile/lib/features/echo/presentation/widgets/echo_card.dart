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
import '../../../../shared/widgets/verified_badges.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:visibility_detector/visibility_detector.dart';
import 'dart:async' show unawaited;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class EchoCard extends StatefulWidget {
  const EchoCard({
    super.key,
    required this.echo,
    this.onTap,
  });

  final EchoEntity echo;
  final VoidCallback? onTap;

  @override
  State<EchoCard> createState() => _EchoCardState();
}

class _EchoCardState extends State<EchoCard> {
  String? _translatedContent;
  String? _translatedTitle;
  bool _isTranslating = false;
  bool _showTranslated = false;

  DateTime? _visibleSince;
  static const _dwellThreshold = Duration(seconds: 3);

  EchoEntity get echo => widget.echo;
  VoidCallback? get onTap => widget.onTap;

  void _openAuthorProfile() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (echo.userId.isNotEmpty && echo.userId == currentUserId) {
      context.push('/profile');
      return;
    }
    context.push('/profile/${Uri.encodeComponent(echo.username)}');
  }

  Future<void> _translate() async {
    if (_isTranslating) return;
    if (_translatedContent != null) {
      setState(() => _showTranslated = !_showTranslated);
      return;
    }
    setState(() => _isTranslating = true);
    try {
      // Using Supabase edge function to proxy translation (keeps API keys server-side).
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) return;
      final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
      final res = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/translate'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': echo.title,
          'content': echo.content,
          'target_lang': 'en',
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _translatedTitle = data['title'] as String?;
          _translatedContent = data['content'] as String?;
          _showTranslated = true;
        });
      }
    } catch (_) {}
    setState(() => _isTranslating = false);
  }

  Future<void> _recordDwell(int seconds) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      // Fire and forget — never block the UI for analytics.
      unawaited(client.rpc('record_dwell_signal', params: {
        'p_user_id': userId,
        'p_echo_id': echo.id,
        'p_category': echo.category.name,
        'p_seconds': seconds,
      }));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('echo_card_${echo.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.5) {
          _visibleSince ??= DateTime.now();
        } else {
          final since = _visibleSince;
          if (since != null) {
            final dwell = DateTime.now().difference(since);
            if (dwell >= _dwellThreshold) {
              _recordDwell(dwell.inSeconds);
            }
          }
          _visibleSince = null;
        }
      },
      child: GestureDetector(
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
              _CardHeader(echo: echo, onAuthorTap: _openAuthorProfile),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (echo.title.isNotEmpty) ...[
                      RichTextDisplay(
                        text: _showTranslated && _translatedTitle != null
                            ? _translatedTitle!
                            : echo.title,
                        style: AppTypography.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    RichTextDisplay(
                      text: _showTranslated && _translatedContent != null
                          ? _translatedContent!
                          : echo.content,
                      style: AppTypography.textTheme.bodyMedium,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (echo.mediaUrls.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _EchoMediaPreview(urls: echo.mediaUrls),
                    ],

                    const SizedBox(height: AppSpacing.xs),
                    // Translation toggle button.
                    GestureDetector(
                      onTap: _translate,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isTranslating)
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: AppColors.fernGreen),
                            )
                          else
                            Icon(
                              _showTranslated
                                  ? Icons.language
                                  : Icons.translate_rounded,
                              size: 12,
                              color: AppColors.textTertiary,
                            ),
                          const SizedBox(width: 4),
                          Text(
                            _showTranslated ? 'Show original' : 'Translate',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontFamily: 'Josefin Sans',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
      ),
    );
  }

  Color _borderColor(EchoStatus status) {
    return switch (status) {
      EchoStatus.verified => AppColors.fernGreen.withValues(alpha: 0.4),
      EchoStatus.disputed => AppColors.sunsetCoral.withValues(alpha: 0.4),
      EchoStatus.controversial =>
        AppColors.statusControversial.withValues(alpha: 0.4),
      EchoStatus.underReview =>
        AppColors.statusUnderReview.withValues(alpha: 0.3),
      EchoStatus.pendingVerification =>
        const Color(0xFF9B59B6).withValues(alpha: 0.3),
      EchoStatus.active => const Color(0xFF3498DB).withValues(alpha: 0.3),
      EchoStatus.hidden => AppColors.borderSubtle,
      EchoStatus.rejected => AppColors.borderSubtle,
    };
  }
}

class _EchoMediaPreview extends StatelessWidget {
  const _EchoMediaPreview({required this.urls});

  final List<String> urls;

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mov');
  }

  @override
  Widget build(BuildContext context) {
    final visible = urls.take(2).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: SizedBox(
        height: visible.length == 1 ? 210 : 160,
        child: Row(
          children: [
            for (int i = 0; i < visible.length; i++) ...[
              Expanded(
                  child: _MediaTile(
                      url: visible[i], isVideo: _isVideo(visible[i]))),
              if (i != visible.length - 1) const SizedBox(width: 2),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return Container(
        color: AppColors.charcoal,
        child: const Center(
          child: Icon(Icons.play_circle_fill_rounded,
              color: AppColors.white, size: 38),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => Container(color: AppColors.softSand),
      errorWidget: (_, __, ___) => Container(
        color: AppColors.softSand,
        child: const Icon(Icons.broken_image_outlined,
            color: AppColors.textTertiary),
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.echo, required this.onAuthorTap});
  final EchoEntity echo;
  final VoidCallback onAuthorTap;

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
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAuthorTap,
      child: _AvatarWithRing(
        avatarUrl: echo.userAvatarUrl,
        userIsVerified: echo.userIsVerified,
        userIsPro: echo.userIsPro,
      ),
    ),
    const SizedBox(width: AppSpacing.sm),
    Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onAuthorTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              echo.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            Text(
              echo.category.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    ),
    TrustBadge(tier: echo.userTrustTier),
    const SizedBox(width: AppSpacing.sm),
    Text(
      echo.timeAgo,
      style: GoogleFonts.josefinSans(
        fontSize: 11,
        color: AppColors.textTertiary,
      ),
    ),
        ],
      ),
    );
  }
}


class _AvatarWithRing extends StatelessWidget {
  const _AvatarWithRing({
    required this.avatarUrl,
    required this.userIsVerified,
    required this.userIsPro,
  });
  final String? avatarUrl;
  final bool userIsVerified;
  final bool userIsPro;

  @override
  Widget build(BuildContext context) {
    const double radius = AppSpacing.avatarSizeSm / 2;
    const double ringWidth = 1.5;
    const double gap = 1.5;
    // Total size = diameter + ring on each side + gap on each side.
    const double totalSize = radius * 2 + (ringWidth + gap) * 2;

    if (!userIsVerified) {
      // No ring — simple avatar.
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.softSand,
        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
        child: avatarUrl == null
            ? const Icon(Icons.person_outline,
                size: 16, color: AppColors.textTertiary)
            : null,
      );
    }

    final badgeType = resolveBadgeType(
      isVerified: userIsVerified,
      isPro: userIsPro,
    );

    final ringColor = switch (badgeType) {
      BadgeType.verifiedPro => const Color(0xFF1DA1F2),
      BadgeType.pro => const Color(0xFFFFB300),
      BadgeType.verified => AppColors.fernGreen,
      BadgeType.none => Colors.transparent,
    };

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: totalSize,
            height: totalSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ringColor,
            ),
          ),
          // Avatar inset.
          Positioned(
            left: ringWidth + gap,
            top: ringWidth + gap,
            child: CircleAvatar(
              radius: radius,
              backgroundColor: AppColors.softSand,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null
                  ? const Icon(Icons.person_outline,
                      size: 16, color: AppColors.textTertiary)
                  : null,
            ),
          ),
          // Tiny verified dot — bottom right.
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: AppColors.fernGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.verified_rounded,
                size: 8,
                color: Colors.white,
              ),
            ),
          ),
        ],
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
          'Controversial',
          const Color(0xFF7A5200),
          const Color(0xFFFFF3E0),
        ),
      EchoStatus.underReview => (
          'Under review',
          const Color(0xFF7A5200),
          const Color(0xFFFFF8E1),
        ),
      EchoStatus.rejected => (
          'Rejected',
          AppColors.sunsetCoralDark,
          AppColors.sunsetCoralLight,
        ),
      EchoStatus.active => (
          'Active',
          const Color(0xFF1A6DB5),
          const Color(0xFFE8F4FD),
        ),
      EchoStatus.pendingVerification => (
          'Awaiting signals',
          const Color(0xFF6B4FA0),
          const Color(0xFFF3EEF9),
        ),
      EchoStatus.hidden => (
          'Hidden',
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
