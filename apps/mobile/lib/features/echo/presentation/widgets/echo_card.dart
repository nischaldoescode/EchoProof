// echo card
// @params echo supplies the feed item model
// @params ontap opens the detail screen when provided

import 'package:flutter/material.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import 'interaction_buttons.dart';
import '../../../../shared/widgets/verified_badges.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../core/utils/media_file_safety.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'dart:async' show unawaited;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../shared/widgets/image_viewer.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../core/services/video_playback_coordinator.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/snack.dart';
import '../../../../shared/widgets/echo_action_sheet.dart';
import '../services/echo_feed_service.dart';
import 'bookmark_button.dart';
import 'echo_video_player.dart';
import 'link_preview_card.dart';

const double _echoThreadAvatarSize = 40;

class EchoCard extends StatefulWidget {
  const EchoCard({
    super.key,
    required this.echo,
    this.onTap,
    this.showReplyPreview = false,
    this.showContextPreview = false,
    this.showThreadTail = false,
  });

  final EchoEntity echo;
  final VoidCallback? onTap;
  final bool showReplyPreview;
  final bool showContextPreview;
  final bool showThreadTail;

  @override
  State<EchoCard> createState() => _EchoCardState();
}

class _EchoCardState extends State<EchoCard> {
  String? _translatedContent;
  String? _translatedTitle;
  bool _isTranslating = false;
  bool _showTranslated = false;
  bool _previewUnavailable = false;

  DateTime? _visibleSince;
  static const _dwellThreshold = Duration(seconds: 3);

  EchoEntity get echo => widget.echo;
  VoidCallback? get onTap => widget.onTap;

  @override
  void didUpdateWidget(covariant EchoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.echo.id != widget.echo.id) {
      _previewUnavailable = false;
    }
  }

  void _openAuthorProfile() {
    _openProfile(echo.username, userId: echo.userId);
  }

  void _openProfile(String username, {String? userId}) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty && userId == currentUserId) {
      context.push('/profile');
      return;
    }
    if (username.trim().isNotEmpty) {
      context.push('/profile/${Uri.encodeComponent(username)}');
    }
  }

  Future<void> _translate() async {
    if (_isTranslating) return;
    if (_translatedContent != null) {
      setState(() => _showTranslated = !_showTranslated);
      return;
    }
    const targetLang = 'en';
    final cacheKey =
        'translation:v1:$targetLang:'
        '${sha256.convert(utf8.encode('${echo.id}|${echo.title}|${echo.content}'))}';
    if (Hive.isBoxOpen('echo_cache')) {
      final cached = Hive.box('echo_cache').get(cacheKey);
      if (cached is Map) {
        setState(() {
          _translatedTitle = cached['title'] as String?;
          _translatedContent = cached['content'] as String?;
          _showTranslated = true;
        });
        return;
      }
    }

    setState(() => _isTranslating = true);
    try {
      // use edge translation so api keys stay server-side
      final client = Supabase.instance.client;
      final session = client.auth.currentSession;
      if (session == null) return;
      final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
      final anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
      final res = await http.post(
        Uri.parse('$supabaseUrl/functions/v1/translate'),
        headers: {
          if (anonKey.isNotEmpty) 'apikey': anonKey,
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': echo.title,
          'content': echo.content,
          'target_lang': targetLang,
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final provider = data['provider'] as String?;
        final hasProvider = provider != 'none';
        if (hasProvider && Hive.isBoxOpen('echo_cache')) {
          await Hive.box('echo_cache').put(cacheKey, {
            'title': data['title'] as String?,
            'content': data['content'] as String?,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
        setState(() {
          _translatedTitle = data['title'] as String?;
          _translatedContent = data['content'] as String?;
          _showTranslated = hasProvider;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  void _openHashtag(String tag) {
    final clean = tag.trim();
    if (clean.length < 2) return;
    context.push('/search?q=${Uri.encodeQueryComponent(clean)}');
  }

  Future<void> _recordDwell(int seconds) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      // fire and forget so analytics never blocks the ui
      unawaited(
        client.rpc(
          'record_dwell_signal',
          params: {
            'p_user_id': userId,
            'p_echo_id': echo.id,
            'p_category': echo.category.name,
            'p_seconds': seconds,
          },
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = extractFirstUrl('${echo.title}\n${echo.content}');
    final hideUrlText = previewUrl != null && !_previewUnavailable;
    final dividerColor = _echoStateBorder(echo);
    final surfaceColor = _echoStateSurface(echo);

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
          margin: const EdgeInsets.fromLTRB(0, 0, 0, AppSpacing.xs),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: surfaceColor,
            border: Border(bottom: BorderSide(color: dividerColor)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showSideMedia =
                  constraints.maxWidth >= 620 && echo.mediaUrls.isNotEmpty;
              final sideMediaWidth = (constraints.maxWidth * 0.34)
                  .clamp(210.0, 280.0)
                  .toDouble();

              final textBody = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (echo.title.isNotEmpty) ...[
                    RichTextDisplay(
                      text: _showTranslated && _translatedTitle != null
                          ? _translatedTitle!
                          : echo.title,
                      style: AppTypography.textTheme.titleMedium?.copyWith(
                        fontSize: 18.5,
                        height: 1.12,
                        color: AppColors.charcoal,
                      ),
                      maxLines: showSideMedia ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      hideUrls: hideUrlText,
                      onHashtagTap: _openHashtag,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  _ExpandableEchoText(
                    text: _showTranslated && _translatedContent != null
                        ? _translatedContent!
                        : echo.content,
                    style: AppTypography.textTheme.bodyMedium?.copyWith(
                      height: 1.34,
                      color: AppColors.textSecondary,
                    ),
                    hideUrls: hideUrlText,
                    onHashtagTap: _openHashtag,
                  ),
                  if (previewUrl != null) ...[
                    EchoLinkPreview(
                      url: previewUrl,
                      onUnavailable: () {
                        if (mounted) {
                          setState(() => _previewUnavailable = true);
                        }
                      },
                    ),
                  ],
                ],
              );

              // keep body content in the same right column as the author row
              // this avoids the avatar height creating a fake gap above title
              final cardRow = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EchoThreadAvatarColumn(
                    avatarUrl: echo.userAvatarUrl,
                    showTail: widget.showThreadTail,
                    onTap: _openAuthorProfile,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _TweetHeader(
                                echo: echo,
                                onAuthorTap: _openAuthorProfile,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _CategoryLabel(
                              category: echo.category,
                              detail: echo.categoryDetail,
                            ),
                          ],
                        ),
                        const SizedBox(height: 1),
                        if (showSideMedia)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: textBody),
                              const SizedBox(width: AppSpacing.lg),
                              SizedBox(
                                width: sideMediaWidth,
                                child: _EchoMediaPreview(
                                  echoId: echo.id,
                                  urls: echo.mediaUrls,
                                  compactHeight: true,
                                ),
                              ),
                            ],
                          )
                        else ...[
                          textBody,
                          if (echo.mediaUrls.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _EchoMediaPreview(
                              echoId: echo.id,
                              urls: echo.mediaUrls,
                            ),
                          ],
                        ],
                        const SizedBox(height: 7),
                        _SignalSummaryLine(echo: echo),
                        const SizedBox(height: 5),
                        // feed cards keep core engagement visible without a dashboard row
                        Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppColors.borderSubtle.withValues(
                                  alpha: 0.64,
                                ),
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: InteractionButtons(
                                  echo: echo,
                                  dense: true,
                                  showMore: false,
                                  showShare: true,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 18,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                color: AppColors.borderSubtle,
                              ),
                              EchoBookmarkButton(
                                echoId: echo.id,
                                compact: true,
                              ),
                              _TranslateButton(
                                isTranslating: _isTranslating,
                                showTranslated: _showTranslated,
                                onTap: _translate,
                              ),
                              _EchoMoreButton(echo: echo),
                            ],
                          ),
                        ),
                        if (widget.showContextPreview &&
                            echo.topContext != null) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _ContextPreviewCard(
                            contextPreview: echo.topContext!,
                            onTap: () {
                              final preview = echo.topContext!;
                              context.push(
                                '/feed/echo/${echo.id}'
                                '?stance=${Uri.encodeComponent(preview.stance)}'
                                '&context=${Uri.encodeComponent(preview.id)}',
                              );
                            },
                            onAuthorTap: (username, userId) =>
                                _openProfile(username, userId: userId),
                          ),
                        ],
                        if (widget.showReplyPreview &&
                            echo.previewReplies.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          EchoReplyPreviewCard(
                            reply: echo.previewReplies.first,
                            totalReplyCount: echo.replyCount,
                            onHashtagTap: _openHashtag,
                            onTap: () => context.push(
                              '/echo/${echo.id}/replies'
                              '?author=${Uri.encodeComponent(echo.username)}'
                              '&content=${Uri.encodeComponent(echo.content)}'
                              '&authorId=${Uri.encodeComponent(echo.userId)}'
                              '${echo.userAvatarUrl == null ? '' : '&avatar=${Uri.encodeComponent(echo.userAvatarUrl!)}'}',
                            ),
                            onAuthorTap: (username, userId) =>
                                _openProfile(username, userId: userId),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );

              if (!widget.showThreadTail) return cardRow;

              // only threaded feed cards pay for intrinsic height
              // it lets the avatar stroke fill the real card height instead of guessing
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: cardRow.children,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

Color _echoStateSurface(EchoEntity echo) {
  if (echo.publicVerdict == 'not_supported') {
    return AppColors.sunsetCoralLight.withValues(alpha: 0.34);
  }
  if (echo.publicVerdict == 'contested') {
    return AppColors.statusControversial.withValues(alpha: 0.045);
  }
  if (echo.publicVerdict == 'insufficient_context' ||
      _isContextWindowEndedOpen(echo)) {
    return AppColors.softSand.withValues(alpha: 0.28);
  }
  if (echo.publicVerdict == 'needs_context') {
    return AppColors.statusUnderReview.withValues(alpha: 0.035);
  }
  if (_isChallengeHeavy(echo)) {
    return AppColors.sunsetCoralLight.withValues(alpha: 0.2);
  }
  return AppColors.white;
}

Color _echoStateBorder(EchoEntity echo) {
  if (echo.publicVerdict == 'not_supported') {
    return AppColors.sunsetCoral.withValues(alpha: 0.18);
  }
  if (echo.publicVerdict == 'contested') {
    return AppColors.statusControversial.withValues(alpha: 0.16);
  }
  if (echo.publicVerdict == 'insufficient_context' ||
      _isContextWindowEndedOpen(echo)) {
    return const Color(0xFFE2DAD0);
  }
  if (_isChallengeHeavy(echo)) {
    return AppColors.sunsetCoral.withValues(alpha: 0.16);
  }
  return AppColors.borderSubtle.withValues(alpha: 0.82);
}

class _SignalSummaryLine extends StatelessWidget {
  const _SignalSummaryLine({required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    final windowEndedOpen = _isContextWindowEndedOpen(echo);
    final challengeHeavy = _isChallengeHeavy(echo);
    final color = switch (echo.publicVerdict) {
      'not_supported' => AppColors.sunsetCoralDark,
      'contested' => AppColors.statusControversial,
      'needs_context' => AppColors.statusUnderReview,
      _ when challengeHeavy => AppColors.sunsetCoralDark,
      _ when windowEndedOpen => const Color(0xFF8A756B),
      _ => AppColors.fernGreenDark,
    };
    final label = switch (echo.publicVerdict) {
      'supported' => 'High confidence',
      'not_supported' => 'Heavily challenged',
      'contested' => 'Context is split',
      'needs_context' => 'Needs context',
      'insufficient_context' => 'Insufficient context',
      _ when windowEndedOpen => 'Window ended',
      _ when challengeHeavy => 'Challenge leading',
      _ => echo.status.displayLabel,
    };
    final confidence = echo.confidenceScore.clamp(0, 100).round();
    final anchored = echo.createdRecordTx?.isNotEmpty == true;

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.10),
          ),
          child: Center(
            child: Icon(
              switch (echo.publicVerdict) {
                'not_supported' => Icons.report_problem_outlined,
                'contested' => Icons.compare_arrows_rounded,
                _ when challengeHeavy => Icons.report_problem_outlined,
                _ => Icons.check_rounded,
              },
              size: 10,
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            '$label • $confidence%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 10.8,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
        if (anchored) ...[
          const SizedBox(width: 5),
          _QuietSolanaGlyph(color: color),
          const SizedBox(width: 2),
          Text(
            '+1 more',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 9.2,
              fontWeight: FontWeight.w700,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuietSolanaGlyph extends StatelessWidget {
  const _QuietSolanaGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Anchored on Solana',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.92, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.08),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Icon(
                Icons.link_rounded,
                size: 9.5,
                color: color.withValues(alpha: 0.82),
              ),
            ),
          );
        },
      ),
    );
  }
}

bool _isContextWindowEndedOpen(EchoEntity echo) {
  final closesAt = echo.publicContextClosesAt;
  return (echo.publicVerdict == 'open' ||
          echo.publicVerdict == 'needs_context') &&
      closesAt != null &&
      !closesAt.isAfter(DateTime.now());
}

bool _isChallengeHeavy(EchoEntity echo) {
  if (echo.publicVerdict == 'not_supported' ||
      echo.publicVerdict == 'needs_context') {
    return true;
  }
  final total = echo.supportCount + echo.challengeCount;
  if (total < 3) return false;
  final challengeShare = echo.challengeCount / total;
  return challengeShare >= 0.62 && echo.challengeCount >= echo.supportCount + 2;
}

class _ContextPreviewCard extends StatelessWidget {
  const _ContextPreviewCard({
    required this.contextPreview,
    required this.onTap,
    required this.onAuthorTap,
  });

  final EchoContextPreview contextPreview;
  final VoidCallback onTap;
  final void Function(String username, String? userId) onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final isSupport = contextPreview.stance == 'support';
    final color = isSupport
        ? AppColors.fernGreenDark
        : AppColors.sunsetCoralDark;
    final extraMedia = contextPreview.mediaUrls.isNotEmpty
        ? ' · ${contextPreview.mediaUrls.length} media'
        : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 2,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => onAuthorTap(
                          contextPreview.username,
                          contextPreview.userId,
                        ),
                        child: AvatarWithBadge(
                          avatarUrl: contextPreview.avatarUrl,
                          radius: 14,
                          badgeType: resolveBadgeType(
                            isVerified: false,
                            isPro: contextPreview.userIsPro,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 5,
                              runSpacing: 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  contextPreview.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.charcoal,
                                  ),
                                ),
                                Text(
                                  isSupport
                                      ? 'added support context'
                                      : 'added challenge context',
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            RichTextDisplay(
                              text: contextPreview.content,
                              style: AppTypography.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              hideUrls: false,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              contextPreview.likeCount > 0
                                  ? '${contextPreview.likeCount} context likes$extraMedia'
                                  : 'Likeable context$extraMedia',
                              style: GoogleFonts.josefinSans(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EchoReplyPreviewCard extends StatefulWidget {
  const EchoReplyPreviewCard({
    super.key,
    required this.reply,
    required this.totalReplyCount,
    required this.onHashtagTap,
    required this.onTap,
    required this.onAuthorTap,
    this.detached = false,
  });

  final EchoReplyPreview reply;
  final int totalReplyCount;
  final ValueChanged<String> onHashtagTap;
  final VoidCallback onTap;
  final void Function(String username, String? userId) onAuthorTap;
  final bool detached;

  @override
  State<EchoReplyPreviewCard> createState() => _EchoReplyPreviewCardState();
}

class _EchoReplyPreviewCardState extends State<EchoReplyPreviewCard> {
  bool _previewUnavailable = false;
  late bool _liked;
  late int _likeCount;
  int _likeBurst = 0;

  @override
  void initState() {
    super.initState();
    _liked = widget.reply.isLiked;
    _likeCount = widget.reply.likeCount;
  }

  @override
  void didUpdateWidget(covariant EchoReplyPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reply.id != widget.reply.id) {
      _previewUnavailable = false;
      _liked = widget.reply.isLiked;
      _likeCount = widget.reply.likeCount;
    }
  }

  Future<void> _toggleLike() async {
    if (showOfflineSnackIfNeeded(context)) return;

    final nextLiked = !_liked;
    final previousLiked = _liked;
    final previousCount = _likeCount;
    setState(() {
      _liked = nextLiked;
      _likeCount = (_likeCount + (nextLiked ? 1 : -1))
          .clamp(0, 1 << 31)
          .toInt();
      if (nextLiked) _likeBurst++;
    });

    try {
      final rows =
          await Supabase.instance.client.rpc(
                'toggle_echo_reply_like',
                params: {'p_reply_id': widget.reply.id},
              )
              as List;
      final row = rows.isEmpty ? null : rows.first as Map<String, dynamic>?;
      if (!mounted || row == null) return;
      final liked = row['liked'] as bool? ?? nextLiked;
      setState(() {
        _liked = liked;
        _likeCount = (row['like_count'] as num?)?.toInt() ?? _likeCount;
      });
      if (liked) {
        unawaited(
          _notifySocialEvent('reply_like', {'reply_id': widget.reply.id}),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = previousLiked;
        _likeCount = previousCount;
      });
      showErrorSnack(context, 'Could not update reply like.');
    }
  }

  Future<void> _notifySocialEvent(
    String event,
    Map<String, dynamic> body,
  ) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-social-event',
        body: {'event': event, ...body},
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = extractFirstUrl(widget.reply.content);
    final hideUrlText = previewUrl != null && !_previewUnavailable;
    final extraReplies = widget.totalReplyCount - 1;
    final showMoreLabel = extraReplies > 0
        ? 'Show more ${extraReplies == 1 ? 'reply' : 'replies'}'
        : 'Reply';
    final detached = widget.detached;

    final thread = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: detached ? AppColors.white : null,
          border: detached
              ? const Border(bottom: BorderSide(color: AppColors.borderSubtle))
              : const Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            detached ? AppSpacing.lg : 0,
            detached ? 7 : AppSpacing.sm,
            detached ? AppSpacing.lg : 0,
            detached ? 12 : 0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: detached ? _echoThreadAvatarSize : 28,
                height: detached ? _echoThreadAvatarSize : 84,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    if (detached)
                      Positioned(
                        top: -7,
                        child: Container(
                          width: 2,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppColors.fernGreen.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    if (!detached)
                      Positioned(
                        top: 4,
                        bottom: 0,
                        child: Container(
                          width: 1.6,
                          decoration: BoxDecoration(
                            color: AppColors.fernGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    if (detached)
                      Positioned(
                        top: 0,
                        child: GestureDetector(
                          onTap: () => widget.onAuthorTap(
                            widget.reply.username,
                            widget.reply.userId,
                          ),
                          child: AvatarWithBadge(
                            avatarUrl: widget.reply.avatarUrl,
                            radius: _echoThreadAvatarSize / 2,
                            badgeType: resolveBadgeType(
                              isVerified: widget.reply.userIsVerified,
                              isPro: widget.reply.userIsPro,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (detached) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!detached)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: widget.reply.isFromFollowed
                              ? AppColors.fernGreenLight
                              : AppColors.surfaceSecondary,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          'recent reply',
                          style: GoogleFonts.josefinSans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: widget.reply.isFromFollowed
                                ? AppColors.fernGreenDark
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!detached) ...[
                          GestureDetector(
                            onTap: () => widget.onAuthorTap(
                              widget.reply.username,
                              widget.reply.userId,
                            ),
                            child: AvatarWithBadge(
                              avatarUrl: widget.reply.avatarUrl,
                              radius: 14,
                              badgeType: resolveBadgeType(
                                isVerified: widget.reply.userIsVerified,
                                isPro: widget.reply.userIsPro,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ReplyPreviewHeader(reply: widget.reply),
                              const SizedBox(height: 3),
                              RichTextDisplay(
                                text: widget.reply.content,
                                style: AppTypography.textTheme.bodySmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                hideUrls: hideUrlText,
                                onHashtagTap: widget.onHashtagTap,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (previewUrl != null)
                      EchoLinkPreview(
                        url: previewUrl,
                        onUnavailable: () {
                          if (mounted) {
                            setState(() => _previewUnavailable = true);
                          }
                        },
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    if (detached && extraReplies > 0) ...[
                      Text(
                        showMoreLabel,
                        style: GoogleFonts.josefinSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.fernGreenDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                    _ReplyPreviewActions(
                      detached: detached,
                      likeCount: _likeCount,
                      isLiked: _liked,
                      likeBurst: _likeBurst,
                      onLike: _toggleLike,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.detached) return thread;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: thread,
    );
  }
}

class _ReplyPreviewActions extends StatelessWidget {
  const _ReplyPreviewActions({
    required this.detached,
    required this.likeCount,
    required this.isLiked,
    required this.likeBurst,
    required this.onLike,
  });

  final bool detached;
  final int likeCount;
  final bool isLiked;
  final int likeBurst;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final color = isLiked ? AppColors.fernGreenDark : AppColors.textTertiary;

    return Row(
      children: [
        Icon(
          Icons.chat_bubble_outline_rounded,
          size: 13,
          color: AppColors.textTertiary,
        ),
        SizedBox(width: detached ? 70 : AppSpacing.md),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLike,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: isLiked ? 1.14 : 1.0,
                    duration: const Duration(milliseconds: 170),
                    curve: Curves.easeOutBack,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        key: ValueKey(isLiked),
                        size: 13,
                        color: isLiked
                            ? AppColors.fernGreen
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    likeCount > 0 ? '$likeCount' : '',
                    style: GoogleFonts.josefinSans(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (likeBurst > 0 && isLiked)
                Positioned(
                  key: ValueKey(likeBurst),
                  left: 1,
                  top: -8,
                  child: _ReplyLikeBurst(color: AppColors.fernGreen),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReplyPreviewHeader extends StatelessWidget {
  const _ReplyPreviewHeader({required this.reply});
  final EchoReplyPreview reply;

  @override
  Widget build(BuildContext context) {
    final created = reply.createdAt;
    final time = created == null ? '' : ' · ${Formatters.timeAgo(created)}';

    return Row(
      children: [
        Flexible(
          child: Text(
            reply.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
          ),
        ),
        if (reply.userIsVerified || reply.userIsPro) ...[
          const SizedBox(width: 4),
          const AccountVerifiedBadge(size: 14),
        ],
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '@${reply.username}$time',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplyLikeBurst extends StatelessWidget {
  const _ReplyLikeBurst({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: (1 - value).clamp(0.0, 1.0).toDouble(),
          child: SizedBox(
            width: 24,
            height: 20,
            child: Stack(
              children: [
                _BurstDot(
                  color: color,
                  offset: Offset(-2 - 4 * value, -2 - 10 * value),
                  scale: 1 - value * 0.35,
                ),
                _BurstDot(
                  color: color.withValues(alpha: 0.75),
                  offset: Offset(7, -6 - 11 * value),
                  scale: 0.82 - value * 0.25,
                ),
                _BurstDot(
                  color: color.withValues(alpha: 0.55),
                  offset: Offset(15 + 4 * value, -1 - 8 * value),
                  scale: 0.68 - value * 0.18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BurstDot extends StatelessWidget {
  const _BurstDot({
    required this.color,
    required this.offset,
    required this.scale,
  });

  final Color color;
  final Offset offset;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: offset,
      child: Transform.scale(
        scale: scale.clamp(0.1, 1.0).toDouble(),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

class _EchoMediaPreview extends StatelessWidget {
  const _EchoMediaPreview({
    required this.echoId,
    required this.urls,
    this.compactHeight = false,
  });

  final String echoId;
  final List<String> urls;
  final bool compactHeight;

  bool _isVideo(String url) {
    return MediaFileSafety.isVideoPath(url);
  }

  @override
  Widget build(BuildContext context) {
    final visible = urls.take(2).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final height = compactHeight
            ? (width * 0.68).clamp(144.0, 190.0).toDouble()
            : visible.length == 1
            ? (width * 0.62).clamp(176.0, 260.0).toDouble()
            : (width * 0.44).clamp(138.0, 188.0).toDouble();

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                for (int i = 0; i < visible.length; i++) ...[
                  Expanded(
                    child: _MediaTile(
                      echoId: echoId,
                      url: visible[i],
                      urls: urls,
                      isVideo: _isVideo(visible[i]),
                    ),
                  ),
                  if (i != visible.length - 1) const SizedBox(width: 2),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.echoId,
    required this.url,
    required this.urls,
    required this.isVideo,
  });

  final String echoId;
  final String url;
  final List<String> urls;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return EchoVideoPlayer(
        url: url,
        playbackId: 'feed_${echoId}_${url.hashCode}',
        compact: true,
        onOpen: () {
          VideoPlaybackCoordinator.instance.pauseAll();
          context.push(
            '/feed/echo/$echoId/video?url=${Uri.encodeComponent(url)}',
          );
        },
      );
    }

    final imageUrls = urls.where((u) => !_isVideoUrl(u)).toList();
    final imageIndex = imageUrls
        .indexOf(url)
        .clamp(0, imageUrls.length - 1)
        .toInt();

    return GestureDetector(
      onTap: () =>
          ImageViewer.show(context, urls: imageUrls, initialIndex: imageIndex),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => Container(color: AppColors.softSand),
        errorWidget: (context, url, error) => Container(
          color: AppColors.softSand,
          child: const Icon(
            Icons.broken_image_outlined,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  bool _isVideoUrl(String value) {
    return MediaFileSafety.isVideoPath(value);
  }
}

class _ExpandableEchoText extends StatefulWidget {
  const _ExpandableEchoText({
    required this.text,
    required this.style,
    required this.hideUrls,
    required this.onHashtagTap,
  });

  final String text;
  final TextStyle? style;
  final bool hideUrls;
  final ValueChanged<String> onHashtagTap;

  @override
  State<_ExpandableEchoText> createState() => _ExpandableEchoTextState();
}

class _ExpandableEchoTextState extends State<_ExpandableEchoText> {
  bool _expanded = false;

  bool get _looksLong =>
      widget.text.length > 220 || '\n'.allMatches(widget.text).length >= 4;

  @override
  void didUpdateWidget(covariant _ExpandableEchoText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichTextDisplay(
            text: widget.text,
            style: widget.style,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            hideUrls: widget.hideUrls,
            onHashtagTap: widget.onHashtagTap,
          ),
          if (_looksLong) ...[
            const SizedBox(height: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'Fold back' : 'Keep reading',
                      style: GoogleFonts.josefinSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.fernGreenDark,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 15,
                        color: AppColors.fernGreenDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TweetHeader extends StatelessWidget {
  const _TweetHeader({required this.echo, required this.onAuthorTap});
  final EchoEntity echo;
  final VoidCallback onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final displayName = echo.userDisplayName.trim().isNotEmpty
        ? echo.userDisplayName.trim()
        : echo.username;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onAuthorTap,
      child: Wrap(
        spacing: 5,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
          ),
          if (echo.userIsVerified || echo.userIsPro)
            _InlineAccountBadge(
              isVerified: echo.userIsVerified,
              isPro: echo.userIsPro,
              size: 13,
            ),
          Text(
            '@${echo.username} · ${echo.timeAgo}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _TranslateButton extends StatelessWidget {
  const _TranslateButton({
    required this.isTranslating,
    required this.showTranslated,
    required this.onTap,
  });

  final bool isTranslating;
  final bool showTranslated;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = showTranslated
        ? 'Original'
        : isTranslating
        ? 'Translating'
        : 'Translate';

    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: SizedBox(
            key: ValueKey('$label-$isTranslating'),
            width: 18,
            height: 18,
            child: Center(
              child: isTranslating
                  ? const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.fernGreen,
                      ),
                    )
                  : Icon(
                      showTranslated ? Icons.language : Icons.translate_rounded,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EchoMoreButton extends StatelessWidget {
  const _EchoMoreButton({required this.echo});

  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l('More actions'),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.more_horiz_rounded, size: 19),
        color: AppColors.textTertiary,
        onPressed: () => showEchoActionSheet(
          context: context,
          echoId: echo.id,
          authorId: echo.userId,
          authorUsername: echo.username,
          onHidden: () => context.read<EchoFeedService>().removeEcho(echo.id),
        ),
      ),
    );
  }
}

class _InlineAccountBadge extends StatelessWidget {
  const _InlineAccountBadge({
    required this.isVerified,
    required this.isPro,
    this.size = 13,
  });

  final bool isVerified;
  final bool isPro;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!isVerified && !isPro) return const SizedBox.shrink();
    return AccountVerifiedBadge(size: size + 2);
  }
}

class _EchoThreadAvatarColumn extends StatelessWidget {
  const _EchoThreadAvatarColumn({
    required this.avatarUrl,
    required this.showTail,
    required this.onTap,
  });

  final String? avatarUrl;
  final bool showTail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const double radius = _echoThreadAvatarSize / 2;
    const double totalSize = radius * 2;

    return SizedBox(
      width: totalSize,
      child: Column(
        mainAxisSize: showTail ? MainAxisSize.max : MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: CircleAvatar(
              radius: radius,
              backgroundColor: AppColors.softSand,
              backgroundImage: avatarImageProvider(avatarUrl),
              child: avatarImageProvider(avatarUrl) == null
                  ? const Icon(
                      Icons.person_outline,
                      size: 19,
                      color: AppColors.textTertiary,
                    )
                  : null,
            ),
          ),
          if (showTail) ...[
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: AppColors.fernGreen.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.category, this.detail});
  final EchoCategory category;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final cleanDetail = detail?.trim();
    final label =
        category == EchoCategory.other &&
            cleanDetail != null &&
            cleanDetail.isNotEmpty
        ? 'Other: $cleanDetail'
        : category.displayName;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(6 * (1 - value), 0),
            child: child,
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 118),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.fernGreenLight.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.8,
              fontWeight: FontWeight.w700,
              color: AppColors.fernGreenDark.withValues(alpha: 0.86),
              fontFamily: AppTypography.fontFamily,
            ),
          ),
        ),
      ),
    );
  }
}
