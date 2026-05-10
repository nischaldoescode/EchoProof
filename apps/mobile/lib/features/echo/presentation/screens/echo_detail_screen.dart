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
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
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
  bool _isLoading = true;
  String? _error;
  double _headerParallax = 0;

  // realtime subscription
  RealtimeChannel? _channel;

  // live values updated by realtime
  double? _liveConfidence;
  EchoStatus? _liveStatus;
  int? _liveSupport;
  int? _liveChallenge;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadEcho();
    _loadProofs();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _headerParallax = (_scrollController.offset * 0.3).clamp(0, 40);
    });
  }

  Future<void> _loadEcho() async {
    try {
      final client = Supabase.instance.client;
      final row = await client.from('echoes').select('''
              id, user_id, title, content, category, status, media_urls, reply_count,
              trust_score, confidence_score, controversy_score,
              support_count, challenge_count, created_at,
              verified_record_tx, verified_record_at, bond_count, response_count,
              users_public!inner(
                username, avatar_url, trust_tier, is_pro
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
            users_public(username)
          ''')
          .eq('echo_id', widget.echoId)
          .order('created_at', ascending: false);

      setState(() => _proofs = List<Map<String, dynamic>>.from(rows));
    } catch (e) {
      AppLogger.warn('echo detail: proofs load failed');
    }
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
      timeAgo: Formatters.timeAgo(created),
    );
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: _DetailShimmer());
    if (_error != null || _echo == null)
      return const Scaffold(body: _DetailError());

    // merge realtime updates over the fetched entity
    final displayed = _echo!.copyWith(
      confidenceScore: _liveConfidence ?? _echo!.confidenceScore,
      status: _liveStatus ?? _echo!.status,
      supportCount: _liveSupport ?? _echo!.supportCount,
      challengeCount: _liveChallenge ?? _echo!.challengeCount,
    );

    return Scaffold(
      backgroundColor: AppColors.white,
      body: CustomScrollView(
        controller: _scrollController,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '@${displayed.username}',
                                      style: AppTypography.textTheme.titleSmall,
                                    ),
                                    Text(
                                      displayed.timeAgo,
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
                    Text(
                      displayed.title,
                      style: AppTypography.textTheme.headlineSmall?.copyWith(
                        height: 1.15,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  Text(
                    displayed.content,
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
                  _LiveScoreSection(echo: displayed),

                  const SizedBox(height: AppSpacing.xl),
                  const Divider(),
                  const SizedBox(height: AppSpacing.lg),

                  // verified record
                  if (displayed.status == EchoStatus.verified) ...[
                    TruthBondButton(
                      echoId: displayed.id,
                      status: displayed.status,
                      bondCount: 0,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // proofs section
                  _ProofsSection(
                    proofs: _proofs,
                    onRefresh: _loadProofs,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EchoDetailMediaGallery extends StatelessWidget {
  const _EchoDetailMediaGallery({required this.urls});

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
        height: visible.length == 1 ? 260 : 180,
        child: Row(
          children: [
            for (int i = 0; i < visible.length; i++) ...[
              Expanded(
                child: _EchoDetailMediaTile(
                  url: visible[i],
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

class _EchoDetailMediaTile extends StatelessWidget {
  const _EchoDetailMediaTile({
    required this.url,
    required this.isVideo,
  });

  final String url;
  final bool isVideo;

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

    return CachedNetworkImage(
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
    );
  }
}

class _LiveScoreSection extends StatelessWidget {
  const _LiveScoreSection({required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Community signals', style: AppTypography.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        ConfidenceBar(confidence: echo.confidenceScore, status: echo.status),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            _SignalChip(
              count: echo.supportCount,
              label: 'Support',
              color: AppColors.fernGreen,
            ),
            const SizedBox(width: AppSpacing.sm),
            _SignalChip(
              count: echo.challengeCount,
              label: 'Challenge',
              color: AppColors.sunsetCoral,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        InteractionButtons(echo: echo),
        const SizedBox(height: AppSpacing.md),
        _BasicStats(echo: echo),
      ],
    );
  }
}

class _BasicStats extends StatelessWidget {
  const _BasicStats({required this.echo});
  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniStat(
            icon: Icons.thumb_up_outlined,
            value: echo.supportCount,
            color: AppColors.fernGreen),
        const SizedBox(width: AppSpacing.md),
        _MiniStat(
            icon: Icons.thumb_down_outlined,
            value: echo.challengeCount,
            color: AppColors.sunsetCoral),
        const SizedBox(width: AppSpacing.md),
        _MiniStat(
            icon: Icons.chat_bubble_outline,
            value: echo.replyCount,
            color: AppColors.charcoal),
        const SizedBox(width: AppSpacing.md),
        _MiniStat(
            icon: Icons.link_outlined,
            value: 0,
            color: const Color(0xFF9C6FDE)),
        const Spacer(),
        Text(
          '${echo.confidenceScore.toStringAsFixed(0)}% confidence',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontFamily: 'Josefin Sans',
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.icon, required this.value, required this.color});
  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          '$value',
          style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontFamily: 'Josefin Sans'),
        ),
      ],
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.count,
    required this.label,
    required this.color,
  });
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: AppTypography.fontFamily,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontFamily: AppTypography.fontFamily,
            ),
          ),
        ],
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
              ),
            );
          }),
      ],
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
