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
import 'interaction_buttons.dart';
import 'solana_status_chip.dart';
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
import '../../../../shared/widgets/image_viewer.dart';
import '../../../../core/services/video_playback_coordinator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/snack.dart';
import 'echo_video_player.dart';
import 'link_preview_card.dart';

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
    final cacheKey = 'translation:v1:$targetLang:'
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
      // Using Supabase edge function to proxy translation (keeps API keys server-side).
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
    final previewUrl = extractFirstUrl('${echo.title}\n${echo.content}');
    final hideUrlText = previewUrl != null && !_previewUnavailable;

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
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openAuthorProfile,
                child: _AvatarWithRing(
                  avatarUrl: echo.userAvatarUrl,
                  userIsVerified: echo.userIsVerified,
                  userIsPro: echo.userIsPro,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (echo.socialContext != null) ...[
                      _SocialContextPill(label: echo.socialContext!),
                      const SizedBox(height: 5),
                    ],
                    _TweetHeader(echo: echo, onAuthorTap: _openAuthorProfile),
                    const SizedBox(height: AppSpacing.xs),
                    if (echo.title.isNotEmpty) ...[
                      RichTextDisplay(
                        text: _showTranslated && _translatedTitle != null
                            ? _translatedTitle!
                            : echo.title,
                        style: AppTypography.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        hideUrls: hideUrlText,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    _ExpandableEchoText(
                      text: _showTranslated && _translatedContent != null
                          ? _translatedContent!
                          : echo.content,
                      style: AppTypography.textTheme.bodyMedium,
                      hideUrls: hideUrlText,
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
                    if (echo.mediaUrls.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      _EchoMediaPreview(echoId: echo.id, urls: echo.mediaUrls),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _CategoryLabel(
                          category: echo.category,
                          detail: echo.categoryDetail,
                        ),
                        _StatusLabel(status: echo.status),
                        SolanaStatusChip(
                          status: echo.solanaStatus,
                          signature: echo.createdRecordTx,
                        ),
                        _TranslateButton(
                          isTranslating: _isTranslating,
                          showTranslated: _showTranslated,
                          onTap: _translate,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ConfidenceBar(
                      confidence: echo.confidenceScore,
                      status: echo.status,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    InteractionButtons(echo: echo, dense: true),
                    if (echo.previewReplies.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ReplyPreviewCard(
                        reply: echo.previewReplies.first,
                        totalReplyCount: echo.replyCount,
                        onTap: () => context.push('/echo/${echo.id}/replies'
                            '?author=${Uri.encodeComponent(echo.username)}'
                            '&content=${Uri.encodeComponent(echo.content)}'
                            '&authorId=${Uri.encodeComponent(echo.userId)}'
                            '${echo.userAvatarUrl == null ? '' : '&avatar=${Uri.encodeComponent(echo.userAvatarUrl!)}'}'),
                        onAuthorTap: (username, userId) =>
                            _openProfile(username, userId: userId),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialContextPill extends StatelessWidget {
  const _SocialContextPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.favorite_rounded,
          size: 12,
          color: AppColors.fernGreenDark,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.fernGreenDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplyPreviewCard extends StatefulWidget {
  const _ReplyPreviewCard({
    required this.reply,
    required this.totalReplyCount,
    required this.onTap,
    required this.onAuthorTap,
  });

  final EchoReplyPreview reply;
  final int totalReplyCount;
  final VoidCallback onTap;
  final void Function(String username, String? userId) onAuthorTap;

  @override
  State<_ReplyPreviewCard> createState() => _ReplyPreviewCardState();
}

class _ReplyPreviewCardState extends State<_ReplyPreviewCard> {
  bool _previewUnavailable = false;
  late bool _liked;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _liked = widget.reply.isLiked;
    _likeCount = widget.reply.likeCount;
  }

  @override
  void didUpdateWidget(covariant _ReplyPreviewCard oldWidget) {
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
      _likeCount =
          (_likeCount + (nextLiked ? 1 : -1)).clamp(0, 1 << 31).toInt();
    });

    try {
      final rows = await Supabase.instance.client.rpc(
        'toggle_echo_reply_like',
        params: {'p_reply_id': widget.reply.id},
      ) as List;
      final row = rows.isEmpty ? null : rows.first as Map<String, dynamic>?;
      if (!mounted || row == null) return;
      setState(() {
        _liked = row['liked'] as bool? ?? nextLiked;
        _likeCount = (row['like_count'] as num?)?.toInt() ?? _likeCount;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = previousLiked;
        _likeCount = previousCount;
      });
      showErrorSnack(context, 'Could not update reply like.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = extractFirstUrl(widget.reply.content);
    final hideUrlText = previewUrl != null && !_previewUnavailable;
    final extraReplies = widget.totalReplyCount - 1;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: AppColors.borderSubtle,
                          borderRadius: BorderRadius.circular(1),
                        ),
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
                    Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 13,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          extraReplies > 0
                              ? '$extraReplies more ${extraReplies == 1 ? 'reply' : 'replies'}'
                              : 'Reply',
                          style: GoogleFonts.josefinSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleLike,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  _liked
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  key: ValueKey(_liked),
                                  size: 13,
                                  color: _liked
                                      ? AppColors.fernGreen
                                      : AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _likeCount > 0 ? '$_likeCount' : 'Like',
                                style: GoogleFonts.josefinSans(
                                  fontSize: 11,
                                  color: _liked
                                      ? AppColors.fernGreenDark
                                      : AppColors.textTertiary,
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
      ),
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
          _InlineAccountBadge(
            isVerified: reply.userIsVerified,
            isPro: reply.userIsPro,
            size: 12,
          ),
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

class _EchoMediaPreview extends StatelessWidget {
  const _EchoMediaPreview({required this.echoId, required this.urls});

  final String echoId;
  final List<String> urls;

  bool _isVideo(String url) {
    return MediaFileSafety.isVideoPath(url);
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
    final imageIndex =
        imageUrls.indexOf(url).clamp(0, imageUrls.length - 1).toInt();

    return GestureDetector(
      onTap: () => ImageViewer.show(
        context,
        urls: imageUrls,
        initialIndex: imageIndex,
      ),
      child: CachedNetworkImage(
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
  });

  final String text;
  final TextStyle? style;
  final bool hideUrls;

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
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            hideUrls: widget.hideUrls,
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
          if (echo.userTrustTier.toLowerCase() != 'unverified')
            _InlineTrustPill(tier: echo.userTrustTier),
        ],
      ),
    );
  }
}

class _InlineTrustPill extends StatelessWidget {
  const _InlineTrustPill({required this.tier});
  final String tier;

  @override
  Widget build(BuildContext context) {
    final label = tier.isEmpty
        ? 'Trusted'
        : '${tier[0].toUpperCase()}${tier.substring(1).toLowerCase()}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.fernGreen.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.josefinSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.fernGreenDark,
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.softSand,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTranslating)
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AppColors.fernGreen,
                ),
              )
            else
              Icon(
                showTranslated ? Icons.language : Icons.translate_rounded,
                size: 12,
                color: AppColors.textTertiary,
              ),
            const SizedBox(width: 4),
            Text(
              showTranslated ? 'Original' : 'Translate',
              style: TextStyle(
                fontSize: 10.5,
                color: AppColors.textTertiary,
                fontFamily: AppTypography.fontFamily,
              ),
            ),
          ],
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
    final badgeType = resolveBadgeType(isVerified: isVerified, isPro: isPro);
    final color = switch (badgeType) {
      BadgeType.verifiedPro => AppColors.fernGreenDark,
      BadgeType.verified => AppColors.fernGreen,
      BadgeType.pro => const Color(0xFFFFB300),
      BadgeType.none => AppColors.textTertiary,
    };
    final icon = switch (badgeType) {
      BadgeType.pro || BadgeType.verifiedPro => Icons.workspace_premium_rounded,
      _ => Icons.verified_rounded,
    };

    return Container(
      width: size + 4,
      height: size + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Icon(icon, size: size * 0.7, color: Colors.white),
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

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.category, this.detail});
  final EchoCategory category;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final cleanDetail = detail?.trim();
    final label = category == EchoCategory.other &&
            cleanDetail != null &&
            cleanDetail.isNotEmpty
        ? 'Other: $cleanDetail'
        : category.displayName;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          fontFamily: AppTypography.fontFamily,
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
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
