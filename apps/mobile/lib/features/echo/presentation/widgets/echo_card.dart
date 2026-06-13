// echo card
// @params echo supplies the feed item model
// @params ontap opens the detail screen when provided

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
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../core/services/video_playback_coordinator.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/snack.dart';
import 'echo_video_player.dart';
import 'link_preview_card.dart';
import '../services/solana_record_retry_service.dart';

class EchoCard extends StatefulWidget {
  const EchoCard({
    super.key,
    required this.echo,
    this.onTap,
    this.showReplyPreview = true,
  });

  final EchoEntity echo;
  final VoidCallback? onTap;
  final bool showReplyPreview;

  @override
  State<EchoCard> createState() => _EchoCardState();
}

class _EchoCardState extends State<EchoCard> {
  String? _translatedContent;
  String? _translatedTitle;
  bool _isTranslating = false;
  bool _showTranslated = false;
  bool _previewUnavailable = false;
  bool _isRetryingSolanaRecord = false;
  String? _solanaStatusOverride;
  String? _createdRecordTxOverride;

  DateTime? _visibleSince;
  static const _dwellThreshold = Duration(seconds: 3);

  EchoEntity get echo => widget.echo;
  VoidCallback? get onTap => widget.onTap;

  @override
  void didUpdateWidget(covariant EchoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.echo.id != widget.echo.id) {
      _previewUnavailable = false;
      _isRetryingSolanaRecord = false;
      _solanaStatusOverride = null;
      _createdRecordTxOverride = null;
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

  Future<void> _retrySolanaRecord() async {
    if (_isRetryingSolanaRecord) return;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != echo.userId) {
      showInfoSnack(context, 'Only the author can retry this record.');
      return;
    }
    setState(() {
      _isRetryingSolanaRecord = true;
      _solanaStatusOverride = 'recording';
    });
    try {
      final signature = await SolanaRecordRetryService.retryEchoCreation(
        echo.id,
      );
      if (!mounted) return;
      setState(() {
        if (signature != null) {
          _createdRecordTxOverride = signature;
          _solanaStatusOverride = 'anchored';
        } else {
          _solanaStatusOverride = 'recording';
        }
      });
      showSuccessSnack(
        context,
        signature == null
            ? 'Solana record retry started.'
            : 'Solana record anchored.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _solanaStatusOverride = 'failed');
      showErrorSnack(context, 'Could not retry the Solana record.');
    } finally {
      if (mounted) setState(() => _isRetryingSolanaRecord = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = extractFirstUrl('${echo.title}\n${echo.content}');
    final hideUrlText = previewUrl != null && !_previewUnavailable;
    final isWindowEndedOpen = _isContextWindowEndedOpen(echo);
    final challengeHeavy = _isChallengeHeavy(echo);
    final cardColor = isWindowEndedOpen
        ? const Color(0xFFFCFAF6)
        : challengeHeavy
        ? const Color(0xFFFFFCFA)
        : AppColors.white;
    final dividerColor = isWindowEndedOpen
        ? const Color(0xFFE2DAD0)
        : challengeHeavy
        ? AppColors.sunsetCoral.withValues(alpha: 0.16)
        : AppColors.borderSubtle.withValues(alpha: 0.82);
    final solanaStatus = _solanaStatusOverride ?? echo.solanaStatus;
    final createdRecordTx = _createdRecordTxOverride ?? echo.createdRecordTx;
    final showSolanaRecord = _shouldShowSolanaRecord(
      echo: echo,
      signature: createdRecordTx,
    );
    final canRetrySolana =
        showSolanaRecord &&
        _canRetrySolanaRecord(
          echo: echo,
          status: solanaStatus,
          signature: createdRecordTx,
        );

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
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(AppSpacing.echoCardRadius),
            border: Border.all(color: dividerColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.026),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
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
                        fontSize: 20,
                        height: 1.16,
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
                      height: 1.42,
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

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (echo.socialContext != null) ...[
                    _SocialContextPill(label: echo.socialContext!),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
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
                  const SizedBox(height: AppSpacing.md),
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
                      const SizedBox(height: AppSpacing.md),
                      _EchoMediaPreview(echoId: echo.id, urls: echo.mediaUrls),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: _PublicVerdictPill(echo: echo)),
                      const SizedBox(width: AppSpacing.sm),
                      _StatusLabel(status: echo.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showSolanaRecord)
                        SolanaStatusChip(
                          status: solanaStatus,
                          signature: createdRecordTx,
                          isRetrying: _isRetryingSolanaRecord,
                          onRetry: canRetrySolana ? _retrySolanaRecord : null,
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
                  if (echo.topContext != null) ...[
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
              );
            },
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

class _PublicVerdictPill extends StatelessWidget {
  const _PublicVerdictPill({required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    final verdict = echo.publicVerdict;
    final windowEndedOpen = _isContextWindowEndedOpen(echo);
    final challengeHeavy = _isChallengeHeavy(echo);
    final color = switch (verdict) {
      'supported' => AppColors.fernGreenDark,
      'not_supported' => AppColors.sunsetCoralDark,
      'contested' => AppColors.statusControversial,
      'needs_context' => AppColors.statusUnderReview,
      'insufficient_context' => AppColors.textSecondary,
      _ when windowEndedOpen => const Color(0xFF8A756B),
      _ when challengeHeavy => AppColors.sunsetCoralDark,
      _ => AppColors.textTertiary,
    };
    final label = switch (verdict) {
      'supported' => 'Supported by public context',
      'not_supported' => 'Not supported by public context',
      'contested' => 'Public context is split',
      'needs_context' => 'Needs public context',
      'insufficient_context' => 'Insufficient public context',
      _ when windowEndedOpen => 'Public context window ended',
      _ when challengeHeavy => 'Challenge context is leading',
      _ => 'Open for public context',
    };
    final window = _contextWindowLabel(echo);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (verdict) {
              'not_supported' => Icons.report_problem_outlined,
              'needs_context' => Icons.fact_check_outlined,
              'insufficient_context' => Icons.hourglass_empty_rounded,
              _ when challengeHeavy => Icons.report_problem_outlined,
              _ when windowEndedOpen => Icons.lock_clock_outlined,
              _ => Icons.groups_2_outlined,
            },
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label · ${echo.supportCount}/${echo.challengeCount} · $window',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _contextWindowLabel(EchoEntity echo) {
  if (echo.publicVerdict != 'open' && echo.publicVerdict != 'needs_context') {
    final decided = echo.publicVerdictAt;
    return decided == null
        ? 'decided'
        : 'decided ${Formatters.timeAgo(decided)}';
  }
  final closesAt = echo.publicContextClosesAt;
  if (closesAt == null) return '7d window';
  final diff = closesAt.difference(DateTime.now());
  if (diff.isNegative) return 'window ended';
  if (diff.inDays >= 1) return '${diff.inDays}d left';
  if (diff.inHours >= 1) return '${diff.inHours}h left';
  return '${diff.inMinutes.clamp(1, 59)}m left';
}

bool _isContextWindowEndedOpen(EchoEntity echo) {
  final closesAt = echo.publicContextClosesAt;
  return (echo.publicVerdict == 'open' ||
          echo.publicVerdict == 'needs_context') &&
      closesAt != null &&
      !closesAt.isAfter(DateTime.now());
}

bool _shouldShowSolanaRecord({
  required EchoEntity echo,
  required String? signature,
}) {
  if (echo.publicVerdict == 'open' || echo.publicVerdict == 'needs_context') {
    return false;
  }
  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  final isOwnEcho = currentUserId != null && currentUserId == echo.userId;
  if (signature != null && signature.isNotEmpty) {
    return echo.publicVerdict == 'supported' || isOwnEcho;
  }
  return isOwnEcho;
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

bool _canRetrySolanaRecord({
  required EchoEntity echo,
  required String status,
  required String? signature,
}) {
  if (echo.publicVerdict == 'open' || echo.publicVerdict == 'needs_context') {
    return false;
  }
  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
  if (currentUserId == null || currentUserId != echo.userId) return false;
  if (signature != null && signature.isNotEmpty) return false;
  return status == 'failed' || status == 'pending';
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
    final followedCue = widget.reply.isFromFollowed
        ? 'reply from someone you follow'
        : 'recent reply';

    final thread = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.only(
          top: widget.detached ? AppSpacing.xs : AppSpacing.sm,
          bottom: widget.detached ? AppSpacing.sm : 0,
        ),
        decoration: widget.detached
            ? null
            : const BoxDecoration(
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
                    if (!widget.detached)
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
                          followedCue,
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
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedScale(
                                    scale: _liked ? 1.14 : 1.0,
                                    duration: const Duration(milliseconds: 170),
                                    curve: Curves.easeOutBack,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
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
                              if (_likeBurst > 0 && _liked)
                                Positioned(
                                  key: ValueKey(_likeBurst),
                                  left: 1,
                                  top: -8,
                                  child: _ReplyLikeBurst(
                                    color: AppColors.fernGreen,
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

    if (!widget.detached) return thread;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        -AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: thread,
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
            maxLines: _expanded ? null : 4,
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
    final isCompact = !isTranslating && !showTranslated;
    final label = showTranslated
        ? 'Original'
        : isTranslating
        ? 'Translating'
        : 'Translate';

    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: isCompact
              ? const EdgeInsets.all(7)
              : const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
          decoration: BoxDecoration(
            color: isCompact ? AppColors.surfaceSecondary : AppColors.softSand,
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            border: Border.all(
              color: AppColors.borderSubtle.withValues(alpha: 0.7),
            ),
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
                  size: isCompact ? 14 : 12,
                  color: AppColors.textTertiary,
                ),
              if (!isCompact) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppColors.textTertiary,
                    fontFamily: AppTypography.fontFamily,
                  ),
                ),
              ],
            ],
          ),
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
      BadgeType.pro => AppColors.fernGreenDark,
      BadgeType.none => AppColors.textTertiary,
    };
    final icon = switch (badgeType) {
      BadgeType.pro || BadgeType.verifiedPro => Icons.verified_rounded,
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
    const double totalSize = radius * 2;

    final badgeType = resolveBadgeType(
      isVerified: userIsVerified,
      isPro: userIsPro,
    );

    final showBadge = badgeType != BadgeType.none;

    return SizedBox(
      width: totalSize + (showBadge ? 4 : 0),
      height: totalSize + (showBadge ? 4 : 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: AppColors.softSand,
            backgroundImage: avatarImageProvider(avatarUrl),
            child: avatarImageProvider(avatarUrl) == null
                ? const Icon(
                    Icons.person_outline,
                    size: 16,
                    color: AppColors.textTertiary,
                  )
                : null,
          ),
          if (showBadge)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: badgeType == BadgeType.verified
                      ? AppColors.fernGreen
                      : AppColors.fernGreenDark,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
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
    final label =
        category == EchoCategory.other &&
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
