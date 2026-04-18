// echo detail screen
// full view of a single echo with proofs, real-time score updates, interaction bar
// subscribes to supabase realtime on this echo's row
// 3d parallax header effect on scroll

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../widgets/confidence_bar.dart';
import '../widgets/trust_badge.dart';
import '../widgets/interaction_buttons.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

// provider scoped to a single echo id
final echoDetailProvider = FutureProvider.family<EchoEntity, String>((ref, echoId) async {
  final client = ref.read(supabaseProvider);
  final row = await client
      .from('echoes')
      .select('''
        id, title, content, category, status,
        trust_score, confidence_score, controversy_score,
        support_count, challenge_count, created_at,
        proof_count:echo_proofs(count),
        users_public!inner(username, avatar_url, trust_tier, is_identity_verified)
      ''')
      .eq('id', echoId)
      .single();
  return _mapRow(row);
});

EchoEntity _mapRow(Map<String, dynamic> row) {
  final user = row['users_public'] as Map<String, dynamic>;
  final proofCountRaw = row['proof_count'] as List?;
  final proofCount = proofCountRaw?.isNotEmpty == true
      ? (proofCountRaw![0]['count'] as int? ?? 0)
      : 0;

  final created = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
  final diff    = DateTime.now().difference(created);
  final timeAgo = diff.inHours < 1
      ? '${diff.inMinutes}m ago'
      : diff.inHours < 24
          ? '${diff.inHours}h ago'
          : '${diff.inDays}d ago';

  return EchoEntity(
    id: row['id'] as String,
    title: row['title'] as String? ?? '',
    content: row['content'] as String,
    username: user['username'] as String,
    userTrustTier: user['trust_tier'] as String? ?? 'unverified',
    userIsVerified: user['is_identity_verified'] as bool? ?? false,
    userAvatarUrl: user['avatar_url'] as String?,
    category: EchoCategory.fromString(row['category'] as String),
    status: _parseStatus(row['status'] as String),
    confidenceScore: (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
    trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
    controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
    supportCount: (row['support_count'] as num?)?.toInt() ?? 0,
    challengeCount: (row['challenge_count'] as num?)?.toInt() ?? 0,
    timeAgo: timeAgo,
    proofCount: proofCount,
  );
}

EchoStatus _parseStatus(String v) => switch (v) {
  'pending_verification' => EchoStatus.pendingVerification,
  'active'               => EchoStatus.active,
  'under_review'         => EchoStatus.underReview,
  'verified'             => EchoStatus.verified,
  'controversial'        => EchoStatus.controversial,
  'disputed'             => EchoStatus.disputed,
  'hidden'               => EchoStatus.hidden,
  'rejected'             => EchoStatus.rejected,
  _                      => EchoStatus.pendingVerification,
};

class EchoDetailScreen extends ConsumerStatefulWidget {
  const EchoDetailScreen({super.key, required this.echoId});
  final String echoId;

  @override
  ConsumerState<EchoDetailScreen> createState() => _EchoDetailScreenState();
}

class _EchoDetailScreenState extends ConsumerState<EchoDetailScreen> {
  final _scrollController = ScrollController();
  double _headerParallax  = 0;
  RealtimeChannel? _channel;

  // local live state — updated by realtime subscription
  double? _liveConfidence;
  EchoStatus? _liveStatus;
  int? _liveSupport;
  int? _liveChallenge;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _subscribeRealtime() {
    final client = ref.read(supabaseProvider);
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
            _liveConfidence = (newRow['confidence_score'] as num?)?.toDouble();
            _liveStatus     = _parseStatus(newRow['status'] as String? ?? 'active');
            _liveSupport    = (newRow['support_count'] as num?)?.toInt();
            _liveChallenge  = (newRow['challenge_count'] as num?)?.toInt();
          });
        },
      )
      .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final echoAsync = ref.watch(echoDetailProvider(widget.echoId));

    return Scaffold(
      backgroundColor: AppColors.white,
      body: echoAsync.when(
        loading: () => const _DetailShimmer(),
        error: (e, _) => const _DetailError(),
        data: (echo) {
          // merge live realtime updates over the fetched entity
          final displayed = echo.copyWith(
            confidenceScore: _liveConfidence ?? echo.confidenceScore,
            status:          _liveStatus     ?? echo.status,
            supportCount:    _liveSupport    ?? echo.supportCount,
            challengeCount:  _liveChallenge  ?? echo.challengeCount,
          );
          return _DetailBody(
            echo: displayed,
            scrollController: _scrollController,
            headerParallax: _headerParallax,
          );
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.echo,
    required this.scrollController,
    required this.headerParallax,
  });

  final EchoEntity echo;
  final ScrollController scrollController;
  final double headerParallax;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        // parallax app bar
        SliverAppBar(
          pinned: true,
          expandedHeight: 120,
          backgroundColor: AppColors.white,
          foregroundColor: AppColors.charcoal,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          shadowColor: AppColors.borderSubtle,
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Transform.translate(
              offset: Offset(0, headerParallax),
              child: Container(
                color: AppColors.softSand,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, 60, AppSpacing.xl, AppSpacing.lg,
                ),
                child: Text(
                  echo.title.isNotEmpty ? echo.title : echo.category.displayName,
                  style: AppTypography.textTheme.headlineSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
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
                    _VerifiedAvatar(
                      avatarUrl: echo.userAvatarUrl,
                      isVerified: echo.userIsVerified,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(echo.username, style: AppTypography.textTheme.titleSmall),
                          Text(echo.timeAgo, style: AppTypography.textTheme.labelMedium),
                        ],
                      ),
                    ),
                    TrustBadge(tier: echo.userTrustTier),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),

                // full content
                Text(echo.content, style: AppTypography.textTheme.bodyLarge),

                const SizedBox(height: AppSpacing.xl),
                const Divider(),
                const SizedBox(height: AppSpacing.lg),

                // live score section — animates on realtime update
                _LiveScoreSection(echo: echo),

                const SizedBox(height: AppSpacing.xl),
                const Divider(),
                const SizedBox(height: AppSpacing.lg),

                // proofs section
                _ProofsSection(echoId: echo.id),
              ],
            ),
          ),
        ),
      ],
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

        // support vs challenge count row
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

        // interaction buttons (same as card)
        InteractionButtons(echo: echo),
      ],
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.count, required this.label, required this.color});
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withOpacity(0.25)),
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

class _ProofsSection extends ConsumerWidget {
  const _ProofsSection({required this.echoId});
  final String echoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: fetch and display proofs from echo_proofs table
    // query: supabase.from('echo_proofs').select('*').eq('echo_id', echoId)
    // for each proof: show type icon (link/image/doc), description, submitter username
    // add an "Add proof" button at the bottom that opens file_picker
    // on file select: upload to storage bucket 'echo-proofs/{echoId}/{uuid}'
    // then insert row into echo_proofs with proof_url and description
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evidence', style: AppTypography.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No evidence attached yet. Be the first to add proof.',
          style: AppTypography.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _VerifiedAvatar extends StatelessWidget {
  const _VerifiedAvatar({required this.avatarUrl, required this.isVerified});
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
              ? const Icon(Icons.person_outline, size: 22, color: AppColors.textTertiary)
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
          const Icon(Icons.error_outline, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.lg),
          Text('Could not load echo', style: AppTypography.textTheme.titleMedium),
        ],
      ),
    );
  }
}