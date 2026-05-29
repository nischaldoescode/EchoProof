// echo detail screen
// full view of a single echo with proofs, realtime score updates, interaction bar
// uses plain StatefulWidget with supabase realtime — no riverpod

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../widgets/confidence_bar.dart';
import '../widgets/trust_badge.dart';
import '../widgets/interaction_buttons.dart';
import '../widgets/signal_response_sheet.dart';
import '../widgets/proof_attachment.dart';
import '../widgets/truth_bond_button.dart';
import '../widgets/verified_echo_record.dart';
import '../widgets/solana_status_chip.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../../shared/widgets/image_viewer.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/media_file_safety.dart';
import '../../../../core/utils/snack.dart';
import '../../../../core/localization/app_copy.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/services/video_playback_coordinator.dart';
import '../widgets/echo_video_player.dart';
import '../widgets/link_preview_card.dart';
import '../services/solana_record_retry_service.dart';

class EchoDetailScreen extends StatefulWidget {
  const EchoDetailScreen({
    super.key,
    required this.echoId,
    this.initialContextStance,
    this.highlightedContextId,
  });

  final String echoId;
  final String? initialContextStance;
  final String? highlightedContextId;

  @override
  State<EchoDetailScreen> createState() => _EchoDetailScreenState();
}

class _EchoDetailScreenState extends State<EchoDetailScreen> {
  final _scrollController = ScrollController();

  EchoEntity? _echo;
  List<Map<String, dynamic>> _proofs = [];
  List<Map<String, dynamic>> _contexts = [];
  List<Map<String, dynamic>> _replies = [];
  bool _isLoading = true;
  bool _isContextsLoading = true;
  bool _isRepliesLoading = true;
  bool _previewUnavailable = false;
  bool _isRetryingPostRecord = false;
  bool _isRetryingVerificationRecord = false;
  String? _error;

  // realtime subscription
  RealtimeChannel? _channel;

  // live values updated by realtime
  double? _liveConfidence;
  EchoStatus? _liveStatus;
  int? _liveSupport;
  int? _liveChallenge;
  int? _liveContextScore;
  String? _livePublicVerdict;
  DateTime? _livePublicVerdictAt;
  DateTime? _livePublicContextClosesAt;
  int? _livePublicContextMinCount;
  String? _livePublicContextDecisionReason;
  int? _liveBondCount;
  String? _liveCreatedRecordTx;
  String? _liveVerifiedRecordTx;
  String? _liveSolanaStatus;
  String? _liveVerifiedRecordStatus;
  DateTime? _liveCreatedRecordAt;
  DateTime? _liveVerifiedRecordAt;

  @override
  void initState() {
    super.initState();
    _loadEcho();
    _loadProofs();
    _loadContexts();
    _loadReplies();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadEcho() async {
    try {
      final client = Supabase.instance.client;
      final row = await client.from('echoes').select('''
              id, user_id, title, content, category, category_detail, status, media_urls, reply_count,
              trust_score, confidence_score, controversy_score,
              support_count, challenge_count, created_at,
              context_support_count, context_challenge_count,
              context_score, public_verdict, public_verdict_at,
              public_context_closes_at, public_context_min_count,
              public_context_decision_reason,
              created_record_tx, created_record_at, solana_status, solana_error,
              verified_record_tx, verified_record_at,
              verified_record_status, verified_record_error,
              bond_count, response_count,
              users_public!inner(
                username, display_name, avatar_url, trust_tier, is_pro
              )
          ''').eq('id', widget.echoId).single();

      setState(() {
        _echo = _mapRow(row);
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('echo detail: load failed', e);
      setState(() {
        _error = 'could not load echo';
        _isLoading = false;
      });
    }
  }

  void _openAuthorProfile(EchoEntity echo) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    if (echo.userId.isNotEmpty && echo.userId == currentUserId) {
      context.push('/profile');
      return;
    }

    if (echo.username.isNotEmpty) {
      context.push('/profile/${Uri.encodeComponent(echo.username)}');
    }
  }

  Future<void> _loadProofs() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('echo_proofs')
          .select('''
            id, proof_type, proof_url, description, created_at,
            stake_tx, solana_status,
            users_public(username)
          ''')
          .eq('echo_id', widget.echoId)
          .order('created_at', ascending: false);

      setState(() => _proofs = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      AppLogger.warn('echo detail: proofs load failed');
    }
  }

  Future<void> _loadContexts() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('signal_responses')
          .select('''
            id, user_id, content, stance, like_count, media_urls, media_types,
            moderation_status, edit_count, last_edited_at, created_at,
            users_public!signal_responses_user_id_fkey(id, username, display_name, avatar_url, trust_tier, is_pro)
          ''')
          .eq('echo_id', widget.echoId)
          .filter('stance', 'in', '("support","challenge")')
          .eq('moderation_status', 'approved')
          .order('like_count', ascending: false)
          .order('created_at', ascending: false)
          .limit(20);

      final contextRows = List<Map<String, dynamic>>.from(rows as List);
      final currentUserId = client.auth.currentUser?.id;
      if (currentUserId != null) {
        final hasOwnContext =
            contextRows.any((row) => row['user_id'] == currentUserId);
        if (!hasOwnContext) {
          final ownRow = await client
              .from('signal_responses')
              .select('''
                id, user_id, content, stance, like_count, media_urls, media_types,
                moderation_status, edit_count, last_edited_at, created_at,
                users_public!signal_responses_user_id_fkey(id, username, display_name, avatar_url, trust_tier, is_pro)
              ''')
              .eq('echo_id', widget.echoId)
              .eq('user_id', currentUserId)
              .maybeSingle();
          if (ownRow != null) {
            contextRows.insert(0, Map<String, dynamic>.from(ownRow));
          }
        }
      }

      if (currentUserId != null && contextRows.isNotEmpty) {
        final responseIds = contextRows.map((row) => row['id']).join(',');
        final likes = await client
            .from('signal_response_likes')
            .select('response_id')
            .eq('user_id', currentUserId)
            .filter('response_id', 'in', '($responseIds)');
        final likedIds = (likes as List)
            .map((row) => (row as Map<String, dynamic>)['response_id'])
            .whereType<String>()
            .toSet();
        for (final row in contextRows) {
          row['is_liked'] = likedIds.contains(row['id']);
        }
      }

      setState(() {
        _contexts = contextRows;
        _isContextsLoading = false;
      });
    } catch (e) {
      AppLogger.warn('echo detail: public context load failed $e');
      setState(() => _isContextsLoading = false);
    }
  }

  Future<void> _loadReplies() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('echo_replies')
          .select('''
            id, content, parent_reply_id, created_at,
            like_count, child_reply_count,
            users_public!inner(id, username, display_name, avatar_url, trust_tier, is_pro)
          ''')
          .eq('echo_id', widget.echoId)
          .order('created_at', ascending: true)
          .limit(6);

      setState(() {
        _replies = List<Map<String, dynamic>>.from(rows as List);
        _isRepliesLoading = false;
      });
    } catch (e) {
      AppLogger.warn('echo detail: replies load failed');
      setState(() => _isRepliesLoading = false);
    }
  }

  void _openReplies(EchoEntity echo) {
    final avatarParam = echo.userAvatarUrl == null
        ? ''
        : '&avatar=${Uri.encodeComponent(echo.userAvatarUrl!)}';

    context.push(
      '/echo/${echo.id}/replies'
      '?author=${Uri.encodeComponent(echo.username)}'
      '&content=${Uri.encodeComponent(echo.content)}'
      '&authorId=${Uri.encodeComponent(echo.userId)}'
      '$avatarParam',
    );
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    _channel = client
        .channel('echo_detail_${widget.echoId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'echoes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.echoId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            if (!mounted) return;
            setState(() {
              _liveConfidence =
                  (newRow['confidence_score'] as num?)?.toDouble();
              _liveStatus =
                  _parseStatus(newRow['status'] as String? ?? 'active');
              _liveSupport =
                  (newRow['context_support_count'] as num?)?.toInt() ??
                      (newRow['support_count'] as num?)?.toInt();
              _liveChallenge =
                  (newRow['context_challenge_count'] as num?)?.toInt() ??
                      (newRow['challenge_count'] as num?)?.toInt();
              _liveContextScore = (newRow['context_score'] as num?)?.toInt();
              _livePublicVerdict = newRow['public_verdict'] as String?;
              _livePublicVerdictAt = _parseDate(newRow['public_verdict_at']);
              _livePublicContextClosesAt =
                  _parseDate(newRow['public_context_closes_at']);
              _livePublicContextMinCount =
                  (newRow['public_context_min_count'] as num?)?.toInt();
              _livePublicContextDecisionReason =
                  newRow['public_context_decision_reason'] as String?;
              _liveBondCount = (newRow['bond_count'] as num?)?.toInt();
              _liveCreatedRecordTx = newRow['created_record_tx'] as String?;
              _liveVerifiedRecordTx = newRow['verified_record_tx'] as String?;
              _liveSolanaStatus = newRow['solana_status'] as String?;
              _liveVerifiedRecordStatus =
                  newRow['verified_record_status'] as String?;
              _liveCreatedRecordAt = _parseDate(newRow['created_record_at']);
              _liveVerifiedRecordAt = _parseDate(newRow['verified_record_at']);
            });
          },
        )
        .subscribe();
  }

  EchoEntity _mapRow(Map<String, dynamic> row) {
    final user = row['users_public'] as Map<String, dynamic>;
    final created =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final trustTier = user['trust_tier'] as String? ?? 'unverified';

    return EchoEntity(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String,
      username: user['username'] as String,
      userDisplayName:
          (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : user['username'] as String,
      userTrustTier: trustTier,
      userIsVerified: trustTier == 'high' || trustTier == 'elite',
      userIsPro: user['is_pro'] as bool? ?? false,
      userAvatarUrl: user['avatar_url'] as String?,
      userId: row['user_id'] as String? ?? '',
      category: EchoCategory.fromString(row['category'] as String),
      categoryDetail: row['category_detail'] as String?,
      status: _parseStatus(row['status'] as String),
      confidenceScore: (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
      trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
      supportCount: (row['context_support_count'] as num?)?.toInt() ??
          (row['support_count'] as num?)?.toInt() ??
          0,
      challengeCount: (row['context_challenge_count'] as num?)?.toInt() ??
          (row['challenge_count'] as num?)?.toInt() ??
          0,
      contextSupportCount: (row['context_support_count'] as num?)?.toInt() ?? 0,
      contextChallengeCount:
          (row['context_challenge_count'] as num?)?.toInt() ?? 0,
      publicVerdict: row['public_verdict'] as String? ?? 'open',
      publicVerdictAt: _parseDate(row['public_verdict_at']),
      publicContextClosesAt: _parseDate(row['public_context_closes_at']),
      publicContextMinCount:
          (row['public_context_min_count'] as num?)?.toInt() ?? 7,
      publicContextDecisionReason:
          row['public_context_decision_reason'] as String?,
      contextScore: (row['context_score'] as num?)?.toInt() ?? 0,
      replyCount: (row['reply_count'] as num?)?.toInt() ?? 0,
      mediaUrls: (row['media_urls'] as List?)?.cast<String>() ?? const [],
      createdRecordTx: row['created_record_tx'] as String?,
      createdRecordAt: _parseDate(row['created_record_at']),
      solanaStatus: row['solana_status'] as String? ?? 'pending',
      solanaError: row['solana_error'] as String?,
      verifiedRecordTx: row['verified_record_tx'] as String?,
      verifiedRecordAt: _parseDate(row['verified_record_at']),
      verifiedRecordStatus:
          row['verified_record_status'] as String? ?? 'pending',
      verifiedRecordError: row['verified_record_error'] as String?,
      bondCount: (row['bond_count'] as num?)?.toInt() ?? 0,
      timeAgo: Formatters.timeAgo(created),
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  EchoStatus _parseStatus(String v) => switch (v) {
        'pending_verification' => EchoStatus.pendingVerification,
        'active' => EchoStatus.active,
        'under_review' => EchoStatus.underReview,
        'verified' => EchoStatus.verified,
        'controversial' => EchoStatus.controversial,
        'disputed' => EchoStatus.disputed,
        'hidden' => EchoStatus.hidden,
        'rejected' => EchoStatus.rejected,
        _ => EchoStatus.pendingVerification,
      };

  void _handleEchoHidden() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/feed');
    }
  }

  void _showContextRules(EchoEntity echo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: const Text('How public context works'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RuleLine(
              icon: Icons.person_add_alt_1_rounded,
              text:
                  'Each user can add one support or challenge context per echo.',
              color: AppColors.fernGreenDark,
            ),
            _RuleLine(
              icon: Icons.edit_note_rounded,
              text:
                  'You can edit your context one time while evaluation is still open.',
              color: AppColors.statusControversial,
            ),
            _RuleLine(
              icon: Icons.favorite_rounded,
              text:
                  'Other users can like context. Likes increase that side of the public decision.',
              color: AppColors.fernGreen,
            ),
            _RuleLine(
              icon: Icons.timer_outlined,
              text:
                  'Evaluation closes after the time window or once enough public context arrives.',
              color: AppColors.textSecondary,
            ),
            _RuleLine(
              icon: Icons.balance_rounded,
              text:
                  'More support means Supported, more challenge means Not supported, and equal weight means Contested.',
              color: AppColors.sunsetCoralDark,
            ),
            _RuleLine(
              icon: Icons.block_rounded,
              text:
                  'If no one adds context before the window closes, the echo is treated as not publicly supported.',
              color: AppColors.sunsetCoralDark,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryPostRecord(EchoEntity echo) async {
    if (_isRetryingPostRecord) return;
    setState(() {
      _isRetryingPostRecord = true;
      _liveSolanaStatus = 'recording';
    });
    try {
      final signature =
          await SolanaRecordRetryService.retryEchoCreation(echo.id);
      if (!mounted) return;
      setState(() {
        if (signature != null) {
          _liveCreatedRecordTx = signature;
          _liveSolanaStatus = 'anchored';
        } else {
          _liveSolanaStatus = 'recording';
        }
      });
      showSuccessSnack(
        context,
        signature == null
            ? 'Solana record retry started.'
            : 'Solana post record anchored.',
      );
      unawaited(_loadEcho());
    } catch (e) {
      if (!mounted) return;
      setState(() => _liveSolanaStatus = 'failed');
      showErrorSnack(context, 'Could not retry the Solana post record.');
    } finally {
      if (mounted) setState(() => _isRetryingPostRecord = false);
    }
  }

  Future<void> _retryVerificationRecord(EchoEntity echo) async {
    if (_isRetryingVerificationRecord) return;
    setState(() {
      _isRetryingVerificationRecord = true;
      _liveVerifiedRecordStatus = 'recording';
    });
    try {
      final signature =
          await SolanaRecordRetryService.retryEchoVerification(echo.id);
      if (!mounted) return;
      setState(() {
        if (signature != null) {
          _liveVerifiedRecordTx = signature;
          _liveVerifiedRecordStatus = 'anchored';
        } else {
          _liveVerifiedRecordStatus = 'recording';
        }
      });
      showSuccessSnack(
        context,
        signature == null
            ? 'Solana verification retry started.'
            : 'Solana verification record anchored.',
      );
      unawaited(_loadEcho());
    } catch (e) {
      if (!mounted) return;
      setState(() => _liveVerifiedRecordStatus = 'failed');
      showErrorSnack(
        context,
        'Could not retry the Solana verification record.',
      );
    } finally {
      if (mounted) setState(() => _isRetryingVerificationRecord = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: _DetailShimmer());
    if (_error != null || _echo == null) {
      return const Scaffold(body: _DetailError());
    }

    // merge realtime updates over the fetched entity
    final displayed = _echo!.copyWith(
      confidenceScore: _liveConfidence ?? _echo!.confidenceScore,
      status: _liveStatus ?? _echo!.status,
      supportCount: _liveSupport ?? _echo!.supportCount,
      challengeCount: _liveChallenge ?? _echo!.challengeCount,
      contextSupportCount: _liveSupport ?? _echo!.contextSupportCount,
      contextChallengeCount: _liveChallenge ?? _echo!.contextChallengeCount,
      contextScore: _liveContextScore ?? _echo!.contextScore,
      publicVerdict: _livePublicVerdict ?? _echo!.publicVerdict,
      publicVerdictAt: _livePublicVerdictAt ?? _echo!.publicVerdictAt,
      publicContextClosesAt:
          _livePublicContextClosesAt ?? _echo!.publicContextClosesAt,
      publicContextMinCount:
          _livePublicContextMinCount ?? _echo!.publicContextMinCount,
      publicContextDecisionReason: _livePublicContextDecisionReason ??
          _echo!.publicContextDecisionReason,
      createdRecordTx: _liveCreatedRecordTx ?? _echo!.createdRecordTx,
      createdRecordAt: _liveCreatedRecordAt ?? _echo!.createdRecordAt,
      solanaStatus: _liveSolanaStatus ?? _echo!.solanaStatus,
      verifiedRecordTx: _liveVerifiedRecordTx ?? _echo!.verifiedRecordTx,
      verifiedRecordAt: _liveVerifiedRecordAt ?? _echo!.verifiedRecordAt,
      verifiedRecordStatus:
          _liveVerifiedRecordStatus ?? _echo!.verifiedRecordStatus,
      bondCount: _liveBondCount ?? _echo!.bondCount,
    );

    final previewUrl =
        extractFirstUrl('${displayed.title}\n${displayed.content}');
    final hideUrlText = previewUrl != null && !_previewUnavailable;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final canRetryPostRecord = _canRetrySolanaRecord(
      currentUserId: currentUserId,
      authorId: displayed.userId,
      status: displayed.solanaStatus,
      signature: displayed.createdRecordTx,
    );
    final canRetryVerificationRecord = _canRetrySolanaRecord(
      currentUserId: currentUserId,
      authorId: displayed.userId,
      status: displayed.verifiedRecordStatus,
      signature: displayed.verifiedRecordTx,
    );

    return Scaffold(
      backgroundColor: AppColors.white,
      body: RefreshIndicator(
        color: AppColors.fernGreen,
        onRefresh: () async {
          await Future.wait([
            _loadEcho(),
            _loadProofs(),
            _loadContexts(),
            _loadReplies(),
          ]);
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.charcoal,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              shadowColor: AppColors.borderSubtle,
              title: _EchoDetailAppBarTitle(echo: displayed),
              actions: [
                _ProofTrailAppBarAction(
                  onPressed: () => context.push(
                    '/feed/echo/${displayed.id}/proof-trail',
                  ),
                ),
                IconButton(
                  tooltip: 'How context works',
                  icon: const Icon(Icons.help_outline_rounded),
                  onPressed: () => _showContextRules(displayed),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // author row
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _openAuthorProfile(displayed),
                              child: Row(
                                children: [
                                  _VerifiedAvatar(
                                    avatarUrl: displayed.userAvatarUrl,
                                    isVerified: displayed.userIsVerified,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayed.userDisplayName
                                                  .trim()
                                                  .isNotEmpty
                                              ? displayed.userDisplayName.trim()
                                              : displayed.username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography
                                              .textTheme.titleSmall,
                                        ),
                                        if (displayed.userIsVerified ||
                                            displayed.userIsPro)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: _InlineDetailBadge(
                                              isVerified:
                                                  displayed.userIsVerified,
                                              isPro: displayed.userIsPro,
                                            ),
                                          ),
                                        Text(
                                          '@${displayed.username} · ${displayed.timeAgo}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography
                                              .textTheme.labelMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          TrustBadge(tier: displayed.userTrustTier),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      if (displayed.title.isNotEmpty) ...[
                        RichTextDisplay(
                          text: displayed.title,
                          style:
                              AppTypography.textTheme.headlineSmall?.copyWith(
                            height: 1.15,
                            color: AppColors.charcoal,
                          ),
                          hideUrls: hideUrlText,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      RichTextDisplay(
                        text: displayed.content,
                        style: AppTypography.textTheme.bodyLarge,
                        hideUrls: hideUrlText,
                      ),

                      if (previewUrl != null)
                        EchoLinkPreview(
                          url: previewUrl,
                          variant: EchoLinkPreviewVariant.detail,
                          onUnavailable: () {
                            if (mounted) {
                              setState(() => _previewUnavailable = true);
                            }
                          },
                        ),

                      if (displayed.mediaUrls.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _EchoDetailMediaGallery(
                          echoId: displayed.id,
                          urls: displayed.mediaUrls,
                        ),
                      ],

                      const SizedBox(height: AppSpacing.xl),
                      _DetailCategoryChip(echo: displayed),
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.lg),

                      // live score section
                      _LiveScoreSection(
                        echo: displayed,
                        onEchoHidden: _handleEchoHidden,
                        onContextPosted: () async {
                          await Future.wait([_loadEcho(), _loadContexts()]);
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          SolanaStatusChip(
                            status: displayed.solanaStatus,
                            signature: displayed.createdRecordTx,
                            label: context.l('Solana post'),
                            compact: false,
                            isRetrying: _isRetryingPostRecord,
                            onRetry: canRetryPostRecord
                                ? () => _retryPostRecord(displayed)
                                : null,
                          ),
                          if (displayed.status == EchoStatus.verified)
                            SolanaStatusChip(
                              status: displayed.verifiedRecordStatus,
                              signature: displayed.verifiedRecordTx,
                              label: context.l('Solana verification'),
                              compact: false,
                              isRetrying: _isRetryingVerificationRecord,
                              onRetry: canRetryVerificationRecord
                                  ? () => _retryVerificationRecord(displayed)
                                  : null,
                            ),
                        ],
                      ),

                      const SizedBox(height: AppSpacing.xl),
                      const Divider(),
                      const SizedBox(height: AppSpacing.lg),

                      _PublicContextSection(
                        echo: displayed,
                        contexts: _contexts,
                        isLoading: _isContextsLoading,
                        initialStance: widget.initialContextStance,
                        highlightedContextId: widget.highlightedContextId,
                        onRefresh: () async {
                          await Future.wait([_loadEcho(), _loadContexts()]);
                        },
                      ),

                      const SizedBox(height: AppSpacing.xl),
                      const Divider(),
                      const SizedBox(height: AppSpacing.lg),

                      // verified record
                      if (displayed.status == EchoStatus.verified) ...[
                        if (displayed.verifiedRecordTx != null &&
                            displayed.verifiedRecordTx!.isNotEmpty) ...[
                          VerifiedEchoRecord(
                            transactionSignature: displayed.verifiedRecordTx!,
                            verifiedAt: displayed.verifiedRecordAt ??
                                displayed.createdRecordAt ??
                                DateTime.now(),
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        TruthBondButton(
                          echoId: displayed.id,
                          status: displayed.status,
                          bondCount: displayed.bondCount,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],

                      // proofs section
                      _ProofsSection(
                        proofs: _proofs,
                        onRefresh: _loadProofs,
                      ),

                      const SizedBox(height: AppSpacing.xl),
                      const Divider(),
                      const SizedBox(height: AppSpacing.lg),

                      _RepliesPreviewSection(
                        replies: _replies,
                        isLoading: _isRepliesLoading,
                        onOpenReplies: () => _openReplies(displayed),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EchoDetailAppBarTitle extends StatelessWidget {
  const _EchoDetailAppBarTitle({required this.echo});

  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    final compactId = echo.id.replaceAll('-', '');
    final shortId =
        compactId.length <= 8 ? compactId : compactId.substring(0, 8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '#echo$shortId',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textTheme.titleSmall?.copyWith(
            color: AppColors.charcoal,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          'by @${echo.username}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ProofTrailAppBarAction extends StatelessWidget {
  const _ProofTrailAppBarAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final showLabel = MediaQuery.sizeOf(context).width >= 430;
    if (!showLabel) {
      return IconButton(
        tooltip: context.l('Proof trail'),
        icon: const Icon(Icons.timeline_rounded),
        onPressed: onPressed,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.timeline_rounded, size: 17),
        label: Text(
          context.l('Proof trail'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.fernGreenDark,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          visualDensity: VisualDensity.compact,
          textStyle: AppTypography.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineDetailBadge extends StatelessWidget {
  const _InlineDetailBadge({
    required this.isVerified,
    required this.isPro,
  });

  final bool isVerified;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final color = isVerified ? AppColors.fernGreen : const Color(0xFFFFB300);
    final label = isVerified && isPro
        ? context.l('Verified Pro')
        : isVerified
            ? context.l('Verified')
            : context.l('Pro');
    final icon = isPro && !isVerified
        ? Icons.workspace_premium_rounded
        : Icons.verified_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 10, color: Colors.white),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EchoDetailMediaGallery extends StatelessWidget {
  const _EchoDetailMediaGallery({required this.echoId, required this.urls});

  final String echoId;
  final List<String> urls;

  bool _isVideo(String url) {
    return MediaFileSafety.isVideoPath(url);
  }

  @override
  Widget build(BuildContext context) {
    final visible = urls.take(2).toList();
    final imageUrls = urls.where((url) => !_isVideo(url)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final height = visible.length == 1
            ? (width * 0.72).clamp(180.0, 260.0).toDouble()
            : (width * 0.45).clamp(128.0, 180.0).toDouble();

        return ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: height,
            child: Row(
              children: [
                for (int i = 0; i < visible.length; i++) ...[
                  Expanded(
                    child: _EchoDetailMediaTile(
                      echoId: echoId,
                      url: visible[i],
                      isVideo: _isVideo(visible[i]),
                      onTap: !_isVideo(visible[i])
                          ? () {
                              final imageIndex = imageUrls.indexOf(visible[i]);
                              ImageViewer.show(
                                context,
                                urls: imageUrls,
                                initialIndex: imageIndex < 0 ? 0 : imageIndex,
                              );
                            }
                          : null,
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

class _EchoDetailMediaTile extends StatelessWidget {
  const _EchoDetailMediaTile({
    required this.echoId,
    required this.url,
    required this.isVideo,
    this.onTap,
  });

  final String echoId;
  final String url;
  final bool isVideo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return EchoVideoPlayer(
        url: url,
        playbackId: 'detail_${echoId}_${url.hashCode}',
        compact: false,
        onOpen: () {
          VideoPlaybackCoordinator.instance.pauseAll();
          context.push(
            '/feed/echo/$echoId/video?url=${Uri.encodeComponent(url)}',
          );
        },
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            placeholder: (_, __) => Container(color: AppColors.softSand),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.softSand,
              child: const Icon(
                Icons.broken_image_outlined,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.sm,
            bottom: AppSpacing.sm,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.48),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.zoom_in_rounded,
                size: 17,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicContextSection extends StatefulWidget {
  const _PublicContextSection({
    required this.echo,
    required this.contexts,
    required this.isLoading,
    required this.onRefresh,
    this.initialStance,
    this.highlightedContextId,
  });

  final EchoEntity echo;
  final List<Map<String, dynamic>> contexts;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final String? initialStance;
  final String? highlightedContextId;

  @override
  State<_PublicContextSection> createState() => _PublicContextSectionState();
}

class _PublicContextSectionState extends State<_PublicContextSection> {
  String _selectedStance = 'support';
  bool _userSelectedStance = false;

  @override
  void initState() {
    super.initState();
    _selectedStance = _normalizeContextStance(widget.initialStance);
  }

  @override
  void didUpdateWidget(covariant _PublicContextSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_userSelectedStance &&
        oldWidget.initialStance != widget.initialStance) {
      _selectedStance = _normalizeContextStance(widget.initialStance);
    }
    if (!_userSelectedStance) {
      final supportRows =
          widget.contexts.where((row) => row['stance'] == 'support').toList();
      final challengeRows =
          widget.contexts.where((row) => row['stance'] == 'challenge').toList();
      if (_selectedStance == 'support' &&
          supportRows.isEmpty &&
          challengeRows.isNotEmpty) {
        _selectedStance = 'challenge';
      } else if (_selectedStance == 'challenge' &&
          challengeRows.isEmpty &&
          supportRows.isNotEmpty) {
        _selectedStance = 'support';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final echo = widget.echo;
    final contexts = widget.contexts;
    final verdict = _publicVerdictLabel(echo.publicVerdict);
    final color = _publicVerdictColor(echo.publicVerdict);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnEcho = currentUserId != null && currentUserId == echo.userId;
    final supportRows =
        contexts.where((row) => row['stance'] == 'support').toList();
    final challengeRows =
        contexts.where((row) => row['stance'] == 'challenge').toList();
    final selectedRows =
        _selectedStance == 'support' ? supportRows : challengeRows;
    Map<String, dynamic>? ownContext;
    if (currentUserId != null) {
      for (final row in contexts) {
        if (row['user_id'] == currentUserId) {
          ownContext = row;
          break;
        }
      }
    }
    final now = DateTime.now();
    final closesAt = echo.publicContextClosesAt;
    final isClosed = echo.publicVerdict != 'open' ||
        (closesAt != null && !closesAt.isAfter(now));
    final windowEndedOpen = echo.publicVerdict == 'open' &&
        closesAt != null &&
        !closesAt.isAfter(now);
    final headerVerdict = windowEndedOpen ? 'Window closed' : verdict;
    final headerColor = windowEndedOpen ? const Color(0xFF8A756B) : color;

    void openSheet(String stance) {
      if (isOwnEcho) {
        showInfoSnack(
          context,
          'You cannot support or challenge your own echo.',
        );
        return;
      }
      if (isClosed) {
        showInfoSnack(
          context,
          'Public context is closed for this echo.',
        );
        return;
      }
      if (ownContext != null) {
        final existingStance = (ownContext['stance'] as String?) == 'challenge'
            ? 'challenge'
            : 'support';
        if (existingStance != stance) {
          showInfoSnack(
            context,
            'You already added $existingStance context. Edit that one instead of adding the other side.',
          );
        }
        stance = existingStance;
      }
      showSignalResponseSheet(
        context: context,
        echoId: echo.id,
        initialStance: stance,
        onPosted: widget.onRefresh,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '#echo context',
                style: AppTypography.textTheme.titleMedium,
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: headerColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(
                  color: headerColor.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                headerVerdict,
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: headerColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _ContextEvaluationNote(echo: echo),
        const SizedBox(height: AppSpacing.md),
        _ContextBalanceBar(
          support: echo.supportCount,
          challenge: echo.challengeCount,
          minCount: echo.publicContextMinCount,
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 360;
            final canAddContext = !isClosed && !isOwnEcho;
            final disabledStyle = OutlinedButton.styleFrom(
              foregroundColor: AppColors.textTertiary,
              disabledForegroundColor: AppColors.textTertiary,
              side: BorderSide(
                color: AppColors.borderMedium.withValues(alpha: 0.7),
              ),
            );
            final supportButton = OutlinedButton.icon(
              onPressed: canAddContext ? () => openSheet('support') : null,
              style: canAddContext ? null : disabledStyle,
              icon: const Icon(Icons.thumb_up_alt_outlined, size: 16),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isClosed ? 'Window closed' : 'Support with context',
                ),
              ),
            );
            final challengeButton = OutlinedButton.icon(
              onPressed: canAddContext ? () => openSheet('challenge') : null,
              style: canAddContext ? null : disabledStyle,
              icon: const Icon(Icons.report_problem_outlined, size: 16),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  isClosed ? 'Window closed' : 'Challenge with context',
                ),
              ),
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  supportButton,
                  const SizedBox(height: AppSpacing.sm),
                  challengeButton,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: supportButton),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: challengeButton),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _ContextTabBar(
          selected: _selectedStance,
          supportCount: echo.supportCount,
          challengeCount: echo.challengeCount,
          onChanged: (stance) => setState(() {
            _userSelectedStance = true;
            _selectedStance = stance;
          }),
        ),
        if (ownContext != null) ...[
          const SizedBox(height: AppSpacing.md),
          _YourContextNotice(
            row: ownContext,
            isClosed: isClosed,
            onEdit: () =>
                openSheet(ownContext!['stance'] as String? ?? 'support'),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (widget.isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (contexts.isEmpty)
          Text(
            'No public context yet. Add a clear reason so the community can decide.',
            style: AppTypography.textTheme.bodySmall,
          )
        else if (selectedRows.isEmpty)
          Text(
            _selectedStance == 'support'
                ? 'No support context yet.'
                : 'No challenge context yet.',
            style: AppTypography.textTheme.bodySmall,
          )
        else
          ...List.generate(selectedRows.length, (index) {
            final row = selectedRows[index];
            return _ContextRow(
              key: ValueKey('context_${row['id']}'),
              row: row,
              isLast: index == selectedRows.length - 1,
              highlighted: row['id'] == widget.highlightedContextId,
              onChanged: widget.onRefresh,
            );
          }),
      ],
    );
  }
}

String _normalizeContextStance(String? value) {
  return value == 'challenge' ? 'challenge' : 'support';
}

class _ContextTabBar extends StatelessWidget {
  const _ContextTabBar({
    required this.selected,
    required this.supportCount,
    required this.challengeCount,
    required this.onChanged,
  });

  final String selected;
  final int supportCount;
  final int challengeCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = selected == 'challenge' ? 1 : 0;
    final selectedColor = selected == 'challenge'
        ? AppColors.sunsetCoralDark
        : AppColors.fernGreenDark;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.softSand,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: selectedIndex == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: selectedColor.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.charcoal.withValues(alpha: 0.07),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _ContextTabButton(
                selected: selected == 'support',
                label: 'Support',
                count: supportCount,
                icon: Icons.thumb_up_alt_outlined,
                color: AppColors.fernGreenDark,
                onTap: () => onChanged('support'),
              ),
              _ContextTabButton(
                selected: selected == 'challenge',
                label: 'Challenge',
                count: challengeCount,
                icon: Icons.report_problem_outlined,
                color: AppColors.sunsetCoralDark,
                onTap: () => onChanged('challenge'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContextTabButton extends StatelessWidget {
  const _ContextTabButton({
    required this.selected,
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: AppTypography.textTheme.labelMedium?.copyWith(
                  color: selected ? color : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ) ??
                TextStyle(
                  color: selected ? color : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontFamily: AppTypography.fontFamily,
                ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? color : AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text('$count $label', maxLines: 1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _YourContextNotice extends StatelessWidget {
  const _YourContextNotice({
    required this.row,
    required this.isClosed,
    required this.onEdit,
  });

  final Map<String, dynamic> row;
  final bool isClosed;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final stance = row['stance'] as String? ?? 'support';
    final editCount = (row['edit_count'] as num?)?.toInt() ?? 0;
    final editsLeft = (1 - editCount).clamp(0, 1).toInt();
    final color = stance == 'support'
        ? AppColors.fernGreenDark
        : AppColors.sunsetCoralDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_pin_circle_outlined, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Your ${stance == 'support' ? 'support' : 'challenge'} context is listed here. ${isClosed ? 'Evaluation is closed.' : editsLeft > 0 ? 'You can edit it once.' : 'You already used your edit.'}',
              style: AppTypography.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: isClosed || editsLeft == 0 ? null : onEdit,
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }
}

class _ContextEvaluationNote extends StatelessWidget {
  const _ContextEvaluationNote({required this.echo});

  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    final total = echo.supportCount + echo.challengeCount;
    final remaining =
        (echo.publicContextMinCount - total).clamp(0, 1 << 31).toInt();
    final closesAt = echo.publicContextClosesAt;
    final verdict = echo.publicVerdict;
    final decidedAt = echo.publicVerdictAt;

    final text = switch (verdict) {
      'supported' ||
      'not_supported' ||
      'contested' =>
        'Decided by public context${decidedAt == null ? '' : ' ${Formatters.timeAgo(decidedAt)}'}.',
      _ when echo.publicContextDecisionReason == 'insufficient_context' =>
        'The review window ended without enough public context, so it is not publicly supported.',
      _ when closesAt != null && !closesAt.isAfter(DateTime.now()) =>
        'The public context window has ended. Existing support and challenge context is still visible.',
      _ when closesAt != null =>
        'Evaluation closes ${_relativeWindow(closesAt)} or after $remaining more context point${remaining == 1 ? '' : 's'}.',
      _ =>
        'Evaluation closes after enough public support or challenge context is received.',
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Text(
        text,
        key: ValueKey(text),
        style: AppTypography.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _ContextBalanceBar extends StatelessWidget {
  const _ContextBalanceBar({
    required this.support,
    required this.challenge,
    required this.minCount,
  });

  final int support;
  final int challenge;
  final int minCount;

  @override
  Widget build(BuildContext context) {
    final total = support + challenge;
    final supportShare = total == 0 ? 0.5 : support / total;
    final progress =
        minCount <= 0 ? 1.0 : (total / minCount).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: SizedBox(
            height: 9,
            child: Row(
              children: [
                Expanded(
                  flex: (supportShare * 1000).round().clamp(1, 999).toInt(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    color: AppColors.fernGreen,
                  ),
                ),
                Expanded(
                  flex:
                      ((1 - supportShare) * 1000).round().clamp(1, 999).toInt(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    color: const Color(0xFFE08A76),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          children: [
            _ContextBalanceLabel(
              '$support support',
              color: AppColors.fernGreenDark,
            ),
            Text(
              '${(progress * 100).round()}% of evaluation threshold',
              style: AppTypography.textTheme.labelSmall,
            ),
            _ContextBalanceLabel(
              '$challenge challenge',
              color: const Color(0xFF9E4A38),
            ),
          ],
        ),
      ],
    );
  }
}

class _ContextBalanceLabel extends StatelessWidget {
  const _ContextBalanceLabel(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ContextRow extends StatefulWidget {
  const _ContextRow({
    super.key,
    required this.row,
    required this.isLast,
    required this.highlighted,
    required this.onChanged,
  });

  final Map<String, dynamic> row;
  final bool isLast;
  final bool highlighted;
  final Future<void> Function() onChanged;

  @override
  State<_ContextRow> createState() => _ContextRowState();
}

class _ContextRowState extends State<_ContextRow> {
  bool _liked = false;
  late int _likeCount;

  @override
  void initState() {
    super.initState();
    _syncFromRow();
  }

  @override
  void didUpdateWidget(covariant _ContextRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row['id'] != widget.row['id'] ||
        oldWidget.row['is_liked'] != widget.row['is_liked'] ||
        oldWidget.row['like_count'] != widget.row['like_count']) {
      _syncFromRow();
    }
  }

  void _syncFromRow() {
    _liked = widget.row['is_liked'] as bool? ?? false;
    _likeCount = (widget.row['like_count'] as num?)?.toInt() ?? 0;
  }

  Future<void> _toggleLike() async {
    if (showOfflineSnackIfNeeded(context)) return;
    final previousLiked = _liked;
    final previousCount = _likeCount;
    setState(() {
      _liked = !_liked;
      _likeCount = (_likeCount + (_liked ? 1 : -1)).clamp(0, 1 << 31).toInt();
    });

    try {
      final rows = await Supabase.instance.client.rpc(
        'toggle_signal_response_like',
        params: {'p_response_id': widget.row['id']},
      ) as List;
      final row = rows.isEmpty ? null : rows.first as Map<String, dynamic>?;
      if (!mounted || row == null) return;
      final liked = row['liked'] as bool? ?? _liked;
      setState(() {
        _liked = liked;
        _likeCount = (row['like_count'] as num?)?.toInt() ?? _likeCount;
      });
      if (liked) {
        unawaited(_notifySocialEvent('context_like', {
          'response_id': widget.row['id'],
        }));
      }
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = previousLiked;
        _likeCount = previousCount;
      });
      final message = e.toString().toLowerCase();
      showErrorSnack(
        context,
        message.contains('public_context_closed')
            ? 'Public context is closed for this echo.'
            : message.contains('own_context')
                ? 'You cannot like your own context.'
                : 'Could not update context like.',
      );
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
    } catch (e) {
      AppLogger.warn('echo detail: social event notify failed $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.row['users_public'] as Map<String, dynamic>? ?? {};
    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
            ? user['display_name'] as String
            : user['username'] as String? ?? 'unknown';
    final username = user['username'] as String? ?? 'unknown';
    final avatarUrl = user['avatar_url'] as String?;
    final stance = widget.row['stance'] as String? ?? 'support';
    final color =
        stance == 'support' ? AppColors.fernGreen : AppColors.sunsetCoralDark;
    final mediaUrls =
        (widget.row['media_urls'] as List?)?.cast<String>() ?? const <String>[];
    final created = _parseContextDate(widget.row['created_at']);

    return Container(
      padding: EdgeInsets.fromLTRB(
        widget.highlighted ? AppSpacing.sm : 0,
        widget.highlighted ? AppSpacing.sm : 0,
        widget.highlighted ? AppSpacing.sm : 0,
        widget.isLast ? 0 : AppSpacing.lg,
      ),
      decoration: widget.highlighted
          ? BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.softSand,
                  backgroundImage: avatarImageProvider(avatarUrl),
                  child: avatarImageProvider(avatarUrl) == null
                      ? const Icon(
                          Icons.person_outline_rounded,
                          size: 15,
                          color: AppColors.textTertiary,
                        )
                      : null,
                ),
                if (!widget.isLast)
                  Container(
                    width: 2,
                    height: AppSpacing.lg,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style: AppTypography.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.charcoal,
                      ),
                    ),
                    Text(
                      '@$username${created == null ? '' : ' · ${Formatters.timeAgo(created)}'}',
                      style: AppTypography.textTheme.labelSmall,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      child: Text(
                        stance == 'support' ? 'Supports' : 'Challenges',
                        style: AppTypography.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                RichTextDisplay(
                  text: widget.row['content'] as String? ?? '',
                  style: AppTypography.textTheme.bodyMedium,
                  hideUrls: false,
                ),
                if (mediaUrls.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _EchoDetailMediaGallery(
                    echoId: 'context_${widget.row['id']}',
                    urls: mediaUrls,
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleLike,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 15,
                          color: _liked
                              ? AppColors.fernGreen
                              : AppColors.textTertiary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _likeCount > 0 ? '$_likeCount' : 'Like context',
                          style: AppTypography.textTheme.labelSmall?.copyWith(
                            color: _liked
                                ? AppColors.fernGreenDark
                                : AppColors.textTertiary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
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

DateTime? _parseContextDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String _relativeWindow(DateTime target) {
  final diff = target.difference(DateTime.now());
  final past = diff.isNegative;
  final duration = past ? diff.abs() : diff;
  final value = duration.inDays >= 1
      ? '${duration.inDays}d'
      : duration.inHours >= 1
          ? '${duration.inHours}h'
          : '${duration.inMinutes.clamp(1, 59)}m';
  return past ? '$value ago' : 'in $value';
}

String _publicVerdictLabel(String verdict) => switch (verdict) {
      'supported' => 'Supported',
      'not_supported' => 'Not supported',
      'contested' => 'Contested',
      _ => 'Open',
    };

Color _publicVerdictColor(String verdict) => switch (verdict) {
      'supported' => AppColors.fernGreenDark,
      'not_supported' => AppColors.sunsetCoralDark,
      'contested' => AppColors.statusControversial,
      _ => AppColors.textTertiary,
    };

bool _canRetrySolanaRecord({
  required String? currentUserId,
  required String authorId,
  required String status,
  required String? signature,
}) {
  if (currentUserId == null || currentUserId != authorId) return false;
  if (signature != null && signature.isNotEmpty) return false;
  return status == 'failed' || status == 'pending';
}

class _LiveScoreSection extends StatelessWidget {
  const _LiveScoreSection({
    required this.echo,
    this.onEchoHidden,
    this.onContextPosted,
  });
  final EchoEntity echo;
  final VoidCallback? onEchoHidden;
  final Future<void> Function()? onContextPosted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tx('echoDetail.communitySignals'),
          style: AppTypography.textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        ConfidenceBar(confidence: echo.confidenceScore, status: echo.status),
        const SizedBox(height: AppSpacing.md),
        InteractionButtons(
          echo: echo,
          onEchoHidden: onEchoHidden,
          onContextPosted: onContextPosted,
        ),
      ],
    );
  }
}

class _DetailCategoryChip extends StatelessWidget {
  const _DetailCategoryChip({required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    final detail = echo.categoryDetail?.trim();
    final label = echo.category == EchoCategory.other &&
            detail != null &&
            detail.isNotEmpty
        ? context.l('Other: {detail}', {'detail': detail})
        : context.l(echo.category.displayName);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Text(
        label,
        style: AppTypography.textTheme.labelLarge?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProofsSection extends StatelessWidget {
  const _ProofsSection({
    required this.proofs,
    required this.onRefresh,
  });
  final List<Map<String, dynamic>> proofs;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tx('echoDetail.evidence'),
            style: AppTypography.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (proofs.isEmpty)
          Text(
            context.l('No evidence attached yet. Be the first to add proof.'),
            style: AppTypography.textTheme.bodySmall,
          )
        else
          ...proofs.map((p) {
            final user = p['users_public'] as Map<String, dynamic>? ?? {};
            final created =
                DateTime.tryParse(p['created_at'] as String? ?? '') ??
                    DateTime.now();
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: ProofAttachment(
                proofType: p['proof_type'] as String? ?? 'url',
                proofUrl: p['proof_url'] as String,
                description: p['description'] as String?,
                username: user['username'] as String? ?? 'unknown',
                timeAgo: Formatters.timeAgo(created),
                stakeTx: p['stake_tx'] as String?,
                solanaStatus: p['solana_status'] as String? ?? 'pending',
              ),
            );
          }),
      ],
    );
  }
}

class _RepliesPreviewSection extends StatelessWidget {
  const _RepliesPreviewSection({
    required this.replies,
    required this.isLoading,
    required this.onOpenReplies,
  });

  final List<Map<String, dynamic>> replies;
  final bool isLoading;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context) {
    final visible = replies.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              replies.isEmpty
                  ? context.tx('echoDetail.replies')
                  : '${context.tx('echoDetail.replies')} (${replies.length})',
              style: AppTypography.textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton(
              onPressed: onOpenReplies,
              child: Text(
                replies.isEmpty
                    ? context.tx('echoDetail.addReply')
                    : context.tx('echoDetail.viewThread'),
                style: const TextStyle(color: AppColors.fernGreenDark),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.fernGreen,
              ),
            ),
          )
        else if (visible.isEmpty)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenReplies,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.softSand,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Text(
                context.l('No replies yet. Start the conversation.'),
                style: AppTypography.textTheme.bodySmall,
              ),
            ),
          )
        else ...[
          for (final reply in visible) _InlineReply(reply: reply),
          if (replies.length > visible.length)
            TextButton.icon(
              onPressed: onOpenReplies,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
              label: Text(context.l('View {count} more', {
                'count': replies.length - visible.length,
              })),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.fernGreenDark,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ],
    );
  }
}

class _InlineReply extends StatefulWidget {
  const _InlineReply({required this.reply});

  final Map<String, dynamic> reply;

  @override
  State<_InlineReply> createState() => _InlineReplyState();
}

class _InlineReplyState extends State<_InlineReply> {
  bool _previewUnavailable = false;

  @override
  void didUpdateWidget(covariant _InlineReply oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reply['id'] != widget.reply['id'] ||
        oldWidget.reply['content'] != widget.reply['content']) {
      _previewUnavailable = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reply = widget.reply;
    final user = reply['users_public'] as Map<String, dynamic>? ?? {};
    final username = user['username'] as String? ?? 'unknown';
    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
            ? user['display_name'] as String
            : username;
    final avatarUrl = user['avatar_url'] as String?;
    final created = DateTime.tryParse(reply['created_at'] as String? ?? '') ??
        DateTime.now();
    final content = reply['content'] as String? ?? '';
    final previewUrl = extractFirstUrl(content);
    final hideUrlText = previewUrl != null && !_previewUnavailable;
    final likeCount = (reply['like_count'] as num?)?.toInt() ?? 0;
    final childReplyCount = (reply['child_reply_count'] as num?)?.toInt() ?? 0;
    final isPro = user['is_pro'] as bool? ?? false;
    final trustTier = user['trust_tier'] as String? ?? 'unverified';
    final isTrusted = trustTier == 'high' || trustTier == 'elite';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VerifiedAvatar(
            avatarUrl: avatarUrl,
            isVerified: isPro || isTrusted,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    if (isPro || isTrusted) ...[
                      Icon(
                        isPro
                            ? Icons.workspace_premium_rounded
                            : Icons.verified_rounded,
                        size: 14,
                        color: isPro
                            ? const Color(0xFFFFB300)
                            : AppColors.fernGreen,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Text(
                        '@$username · ${Formatters.timeAgo(created)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                RichTextDisplay(
                  text: content,
                  style: AppTypography.textTheme.bodyMedium,
                  hideUrls: hideUrlText,
                ),
                if (previewUrl != null)
                  EchoLinkPreview(
                    url: previewUrl,
                    variant: EchoLinkPreviewVariant.compact,
                    onUnavailable: () {
                      if (mounted) {
                        setState(() => _previewUnavailable = true);
                      }
                    },
                  ),
                if (likeCount > 0 || childReplyCount > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (likeCount > 0) ...[
                        const Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: AppColors.sunsetCoral,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          Formatters.compactNumber(likeCount),
                          style: AppTypography.textTheme.labelSmall,
                        ),
                      ],
                      if (likeCount > 0 && childReplyCount > 0)
                        const SizedBox(width: AppSpacing.md),
                      if (childReplyCount > 0) ...[
                        const Icon(
                          Icons.mode_comment_outlined,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          Formatters.compactNumber(childReplyCount),
                          style: AppTypography.textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifiedAvatar extends StatelessWidget {
  const _VerifiedAvatar({
    required this.avatarUrl,
    required this.isVerified,
  });
  final String? avatarUrl;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppSpacing.avatarSizeMd + 4,
      height: AppSpacing.avatarSizeMd + 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isVerified ? AppColors.fernGreen : AppColors.borderSubtle,
          width: isVerified ? 2.0 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: CircleAvatar(
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
      ),
    );
  }
}

class _DetailShimmer extends StatelessWidget {
  const _DetailShimmer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.xl),
      child: EchoCardShimmer(),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Could not load echo',
            style: AppTypography.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
