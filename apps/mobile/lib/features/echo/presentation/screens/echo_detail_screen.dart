// echo detail screen
// full view of a single echo with proofs, realtime score updates, interaction bar
// uses plain StatefulWidget with supabase realtime — no riverpod

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
import '../widgets/proof_attachment.dart';
import '../widgets/truth_bond_button.dart';
import '../widgets/verified_echo_record.dart';
import '../widgets/solana_status_chip.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../../shared/widgets/image_viewer.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/media_file_safety.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EchoDetailScreen extends StatefulWidget {
  const EchoDetailScreen({super.key, required this.echoId});
  final String echoId;

  @override
  State<EchoDetailScreen> createState() => _EchoDetailScreenState();
}

class _EchoDetailScreenState extends State<EchoDetailScreen> {
  final _scrollController = ScrollController();

  EchoEntity? _echo;
  List<Map<String, dynamic>> _proofs = [];
  List<Map<String, dynamic>> _replies = [];
  bool _isLoading = true;
  bool _isRepliesLoading = true;
  String? _error;

  // realtime subscription
  RealtimeChannel? _channel;

  // live values updated by realtime
  double? _liveConfidence;
  EchoStatus? _liveStatus;
  int? _liveSupport;
  int? _liveChallenge;
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
              id, user_id, title, content, category, status, media_urls, reply_count,
              trust_score, confidence_score, controversy_score,
              support_count, challenge_count, created_at,
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

  Future<void> _loadReplies() async {
    try {
      final client = Supabase.instance.client;
      final rows = await client
          .from('echo_replies')
          .select('''
            id, content, parent_reply_id, created_at,
            users_public!inner(id, username, display_name, avatar_url, trust_tier)
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
              _liveSupport = (newRow['support_count'] as num?)?.toInt();
              _liveChallenge = (newRow['challenge_count'] as num?)?.toInt();
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

    return EchoEntity(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String,
      username: user['username'] as String,
      userDisplayName:
          (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : user['username'] as String,
      userTrustTier: user['trust_tier'] as String? ?? 'unverified',
      userIsVerified: false,
      userIsPro: user['is_pro'] as bool? ?? false,
      userAvatarUrl: user['avatar_url'] as String?,
      userId: row['user_id'] as String? ?? '',
      category: EchoCategory.fromString(row['category'] as String),
      status: _parseStatus(row['status'] as String),
      confidenceScore: (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
      trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
      supportCount: (row['support_count'] as num?)?.toInt() ?? 0,
      challengeCount: (row['challenge_count'] as num?)?.toInt() ?? 0,
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
      createdRecordTx: _liveCreatedRecordTx ?? _echo!.createdRecordTx,
      createdRecordAt: _liveCreatedRecordAt ?? _echo!.createdRecordAt,
      solanaStatus: _liveSolanaStatus ?? _echo!.solanaStatus,
      verifiedRecordTx: _liveVerifiedRecordTx ?? _echo!.verifiedRecordTx,
      verifiedRecordAt: _liveVerifiedRecordAt ?? _echo!.verifiedRecordAt,
      verifiedRecordStatus:
          _liveVerifiedRecordStatus ?? _echo!.verifiedRecordStatus,
      bondCount: _liveBondCount ?? _echo!.bondCount,
    );

    return Scaffold(
      backgroundColor: AppColors.white,
      body: RefreshIndicator(
        color: AppColors.fernGreen,
        onRefresh: () async {
          await Future.wait([
            _loadEcho(),
            _loadProofs(),
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
              title: Text('Echo', style: AppTypography.textTheme.titleMedium),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
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
                                        style:
                                            AppTypography.textTheme.titleSmall,
                                      ),
                                      Text(
                                        '@${displayed.username} · ${displayed.timeAgo}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            AppTypography.textTheme.labelMedium,
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
                        style: AppTypography.textTheme.headlineSmall?.copyWith(
                          height: 1.15,
                          color: AppColors.charcoal,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    RichTextDisplay(
                      text: displayed.content,
                      style: AppTypography.textTheme.bodyLarge,
                    ),

                    if (displayed.mediaUrls.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _EchoDetailMediaGallery(urls: displayed.mediaUrls),
                    ],

                    const SizedBox(height: AppSpacing.xl),
                    const Divider(),
                    const SizedBox(height: AppSpacing.lg),

                    // live score section
                    _LiveScoreSection(
                      echo: displayed,
                      onEchoHidden: _handleEchoHidden,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        SolanaStatusChip(
                          status: displayed.solanaStatus,
                          signature: displayed.createdRecordTx,
                          label: 'Solana post',
                          compact: false,
                        ),
                        if (displayed.status == EchoStatus.verified)
                          SolanaStatusChip(
                            status: displayed.verifiedRecordStatus,
                            signature: displayed.verifiedRecordTx,
                            label: 'Solana verification',
                            compact: false,
                          ),
                      ],
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
          ],
        ),
      ),
    );
  }
}

class _EchoDetailMediaGallery extends StatelessWidget {
  const _EchoDetailMediaGallery({required this.urls});

  final List<String> urls;

  bool _isVideo(String url) {
    return MediaFileSafety.isVideoPath(url);
  }

  @override
  Widget build(BuildContext context) {
    final visible = urls.take(2).toList();
    final imageUrls = urls.where((url) => !_isVideo(url)).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: SizedBox(
        height: visible.length == 1 ? 260 : 180,
        child: Row(
          children: [
            for (int i = 0; i < visible.length; i++) ...[
              Expanded(
                child: _EchoDetailMediaTile(
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
  }
}

class _EchoDetailMediaTile extends StatelessWidget {
  const _EchoDetailMediaTile({
    required this.url,
    required this.isVideo,
    this.onTap,
  });

  final String url;
  final bool isVideo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return Container(
        color: AppColors.charcoal,
        child: const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            color: AppColors.white,
            size: 44,
          ),
        ),
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

class _LiveScoreSection extends StatelessWidget {
  const _LiveScoreSection({required this.echo, this.onEchoHidden});
  final EchoEntity echo;
  final VoidCallback? onEchoHidden;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Community signals', style: AppTypography.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        ConfidenceBar(confidence: echo.confidenceScore, status: echo.status),
        const SizedBox(height: AppSpacing.md),
        InteractionButtons(echo: echo, onEchoHidden: onEchoHidden),
      ],
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
        Text('Evidence', style: AppTypography.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (proofs.isEmpty)
          Text(
            'No evidence attached yet. Be the first to add proof.',
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
              replies.isEmpty ? 'Replies' : 'Replies (${replies.length})',
              style: AppTypography.textTheme.titleMedium,
            ),
            const Spacer(),
            TextButton(
              onPressed: onOpenReplies,
              child: Text(
                replies.isEmpty ? 'Add reply' : 'View thread',
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
                'No replies yet. Start the conversation.',
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
              label: Text('View ${replies.length - visible.length} more'),
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

class _InlineReply extends StatelessWidget {
  const _InlineReply({required this.reply});

  final Map<String, dynamic> reply;

  @override
  Widget build(BuildContext context) {
    final user = reply['users_public'] as Map<String, dynamic>? ?? {};
    final username = user['username'] as String? ?? 'unknown';
    final displayName =
        (user['display_name'] as String?)?.trim().isNotEmpty == true
            ? user['display_name'] as String
            : username;
    final avatarUrl = user['avatar_url'] as String?;
    final created = DateTime.tryParse(reply['created_at'] as String? ?? '') ??
        DateTime.now();

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
          _VerifiedAvatar(avatarUrl: avatarUrl, isVerified: false),
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
                  text: reply['content'] as String? ?? '',
                  style: AppTypography.textTheme.bodyMedium,
                ),
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
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null
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
