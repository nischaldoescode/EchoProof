// proof trail screen
// timeline view of evidence, public context, records, and bonds for one echo

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/rich_text_display.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../widgets/confidence_bar.dart';
import '../widgets/solana_status_chip.dart';
import '../widgets/trust_badge.dart';

class ProofTrailScreen extends StatefulWidget {
  const ProofTrailScreen({super.key, required this.echoId});

  final String echoId;

  @override
  State<ProofTrailScreen> createState() => _ProofTrailScreenState();
}

class _ProofTrailScreenState extends State<ProofTrailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  EchoEntity? _echo;
  DateTime? _echoCreatedAt;
  List<Map<String, dynamic>> _proofs = [];
  List<Map<String, dynamic>> _contexts = [];
  Map<String, dynamic>? _ownBond;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _loadTrail();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadTrail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final currentUserId = client.auth.currentUser?.id;

      final results = await Future.wait<dynamic>([
        client.from('echoes').select('''
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
              bond_count,
              users_public!inner(
                username, display_name, avatar_url, trust_tier, is_pro
              )
          ''').eq('id', widget.echoId).single(),
        client
            .from('echo_proofs')
            .select('''
              id, proof_type, proof_url, description, created_at,
              stake_tx, solana_status, solana_record_at,
              users_public(username, display_name, avatar_url, trust_tier, is_pro)
            ''')
            .eq('echo_id', widget.echoId)
            .order('created_at', ascending: true)
            .limit(40),
        client
            .from('signal_responses')
            .select('''
              id, user_id, content, stance, like_count, media_urls, media_types,
              moderation_status, created_at,
              users_public!signal_responses_user_id_fkey(
                id, username, display_name, avatar_url, trust_tier, is_pro
              )
            ''')
            .eq('echo_id', widget.echoId)
            .filter('stance', 'in', '("support","challenge")')
            .eq('moderation_status', 'approved')
            .order('created_at', ascending: true)
            .limit(40),
        if (currentUserId == null)
          Future<dynamic>.value(null)
        else
          client
              .from('truth_bonds')
              .select('''
                id, user_id, mint_tx, bond_status, solana_status,
                created_at, settles_at, settled_at, contested_at
              ''')
              .eq('echo_id', widget.echoId)
              .eq('user_id', currentUserId)
              .maybeSingle(),
      ]);

      if (!mounted) return;

      _entranceController.reset();
      setState(() {
        _echo = _mapEchoRow(results[0] as Map<String, dynamic>);
        _echoCreatedAt = _parseDate(
          (results[0] as Map<String, dynamic>)['created_at'],
        );
        _proofs = List<Map<String, dynamic>>.from(results[1] as List);
        _contexts = List<Map<String, dynamic>>.from(results[2] as List);
        _ownBond = results[3] as Map<String, dynamic>?;
        _isLoading = false;
      });
      await _entranceController.forward();
    } catch (e) {
      AppLogger.error('proof trail: load failed', e);
      if (!mounted) return;
      setState(() {
        _error = context.l('Could not load proof trail.');
        _isLoading = false;
      });
    }
  }

  EchoEntity _mapEchoRow(Map<String, dynamic> row) {
    final user = row['users_public'] as Map<String, dynamic>? ?? {};
    final created =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final trustTier = user['trust_tier'] as String? ?? 'unverified';

    return EchoEntity(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String? ?? '',
      username: user['username'] as String? ?? 'unknown',
      userDisplayName:
          (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : user['username'] as String? ?? 'unknown',
      userTrustTier: trustTier,
      userIsVerified: trustTier == 'high' || trustTier == 'elite',
      userAvatarUrl: user['avatar_url'] as String?,
      userIsPro: user['is_pro'] as bool? ?? false,
      userId: row['user_id'] as String? ?? '',
      category: EchoCategory.fromString(row['category'] as String? ?? 'other'),
      categoryDetail: row['category_detail'] as String?,
      status: EchoStatus.fromString(row['status'] as String? ?? 'active'),
      confidenceScore: (row['confidence_score'] as num?)?.toDouble() ?? 0,
      trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0,
      supportCount: (row['context_support_count'] as num?)?.toInt() ??
          (row['support_count'] as num?)?.toInt() ??
          0,
      challengeCount: (row['context_challenge_count'] as num?)?.toInt() ??
          (row['challenge_count'] as num?)?.toInt() ??
          0,
      contextSupportCount: (row['context_support_count'] as num?)?.toInt() ?? 0,
      contextChallengeCount:
          (row['context_challenge_count'] as num?)?.toInt() ?? 0,
      contextScore: (row['context_score'] as num?)?.toInt() ?? 0,
      publicVerdict: row['public_verdict'] as String? ?? 'open',
      publicVerdictAt: _parseDate(row['public_verdict_at']),
      publicContextClosesAt: _parseDate(row['public_context_closes_at']),
      publicContextMinCount:
          (row['public_context_min_count'] as num?)?.toInt() ?? 7,
      publicContextDecisionReason:
          row['public_context_decision_reason'] as String?,
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
      mediaUrls: (row['media_urls'] as List?)?.cast<String>() ?? const [],
      replyCount: (row['reply_count'] as num?)?.toInt() ?? 0,
      timeAgo: Formatters.timeAgo(created),
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(title: Text(context.l('Proof trail'))),
        body: const _ProofTrailLoading(),
      );
    }

    if (_error != null || _echo == null) {
      return Scaffold(
        backgroundColor: AppColors.white,
        appBar: AppBar(title: Text(context.l('Proof trail'))),
        body: _ProofTrailError(message: _error ?? context.l('Echo not found.')),
      );
    }

    final echo = _echo!;
    final events = _buildEvents(echo);
    final hasCommunityTrail = _proofs.isNotEmpty ||
        _contexts.isNotEmpty ||
        _hasMeaningfulRecord(echo.solanaStatus, echo.createdRecordTx) ||
        _hasMeaningfulRecord(
          echo.verifiedRecordStatus,
          echo.verifiedRecordTx,
        ) ||
        echo.publicVerdict != 'open' ||
        echo.bondCount > 0 ||
        _ownBond != null;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(
          context.l('Proof trail'),
          style: AppTypography.textTheme.titleLarge,
        ),
        actions: [
          IconButton(
            tooltip: context.l('Refresh proof trail'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadTrail,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.fernGreen,
        onRefresh: _loadTrail,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth =
                constraints.maxWidth >= 760 ? 720.0 : double.infinity;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FadeTransition(
                          opacity: _entranceController,
                          child: _ProofTrailHeader(
                            echo: echo,
                            proofCount: _proofs.length,
                            contextCount: _contexts.length,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (!hasCommunityTrail) ...[
                          _AnimatedTrailItem(
                            controller: _entranceController,
                            index: 0,
                            child: const _ProofTrailEmptyState(),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        ...List.generate(events.length, (index) {
                          return _AnimatedTrailItem(
                            controller: _entranceController,
                            index: index + 1,
                            child: _ProofTrailEventTile(
                              event: events[index],
                              isLast: index == events.length - 1,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _hasMeaningfulRecord(String status, String? signature) {
    return signature?.trim().isNotEmpty == true ||
        status == 'recording' ||
        status == 'anchored' ||
        status == 'failed';
  }

  List<_ProofTrailEvent> _buildEvents(EchoEntity echo) {
    final events = <_ProofTrailEvent>[
      _ProofTrailEvent(
        title: context.l('Echo created'),
        body: context.l('@{username} published this echo.', {
          'username': echo.username,
        }),
        time: _echoCreatedAt,
        displayTime: echo.timeAgo,
        icon: Icons.article_outlined,
        color: AppColors.charcoal,
        chips: [
          _TrailChipData(
            label: echo.category.displayName,
            icon: Icons.category_outlined,
            color: AppColors.charcoal,
          ),
        ],
        content: echo.title.isNotEmpty ? echo.title : echo.content,
      ),
    ];

    if (_hasMeaningfulRecord(echo.solanaStatus, echo.createdRecordTx)) {
      events.add(
        _ProofTrailEvent(
          title: _recordTitle(
            status: echo.solanaStatus,
            anchored: context.l('Creation record anchored'),
            pending: context.l('Creation record pending'),
            failed: context.l('Creation record failed'),
          ),
          body: context.l(
            'The original echo record is tracked separately from public context.',
          ),
          time: echo.createdRecordAt,
          displayTime: _timeLabel(echo.createdRecordAt),
          icon: Icons.link_rounded,
          color: _recordColor(echo.solanaStatus),
          solanaStatus: echo.solanaStatus,
          signature: echo.createdRecordTx,
          signatureLabel: context.l('Solana post'),
        ),
      );
    }

    for (final proof in _proofs) {
      final user = proof['users_public'] as Map<String, dynamic>? ?? {};
      final created = _parseDate(proof['created_at']);
      final type = proof['proof_type'] as String? ?? 'url';
      final solanaStatus = proof['solana_status'] as String? ?? 'pending';
      events.add(
        _ProofTrailEvent(
          title: context.l('Evidence added'),
          body: _proofBody(type, user),
          time: created,
          displayTime: _timeLabel(created),
          icon: _proofIcon(type),
          color: AppColors.fernGreenDark,
          content: proof['description'] as String?,
          mediaUrl: type == 'image' ? proof['proof_url'] as String? : null,
          chips: [
            _TrailChipData(
              label: _proofTypeLabel(type),
              icon: _proofIcon(type),
              color: AppColors.fernGreenDark,
            ),
          ],
          solanaStatus: solanaStatus,
          signature: proof['stake_tx'] as String?,
          signatureLabel: context.l('Solana proof'),
        ),
      );
    }

    for (final row in _contexts) {
      final stance =
          (row['stance'] as String?) == 'challenge' ? 'challenge' : 'support';
      final user = row['users_public'] as Map<String, dynamic>? ?? {};
      final created = _parseDate(row['created_at']);
      final likeCount = (row['like_count'] as num?)?.toInt() ?? 0;
      final color = stance == 'support'
          ? AppColors.fernGreenDark
          : AppColors.sunsetCoralDark;
      events.add(
        _ProofTrailEvent(
          title: stance == 'support'
              ? context.l('Support context added')
              : context.l('Challenge context added'),
          body: _contextBody(stance, user),
          time: created,
          displayTime: _timeLabel(created),
          icon: stance == 'support'
              ? Icons.thumb_up_alt_outlined
              : Icons.report_problem_outlined,
          color: color,
          content: row['content'] as String?,
          mediaUrl: _firstMediaUrl(row),
          chips: [
            _TrailChipData(
              label: stance == 'support'
                  ? context.l('Support')
                  : context.l('Challenge'),
              icon: stance == 'support'
                  ? Icons.thumb_up_alt_outlined
                  : Icons.report_problem_outlined,
              color: color,
            ),
            if (likeCount > 0)
              _TrailChipData(
                label: context.l('{count} likes', {'count': likeCount}),
                icon: Icons.favorite_border_rounded,
                color: AppColors.fernGreenDark,
              ),
          ],
        ),
      );
    }

    if (echo.publicVerdict != 'open') {
      events.add(
        _ProofTrailEvent(
          title: context.l('Public context decided'),
          body: _verdictBody(echo),
          time: echo.publicVerdictAt ?? echo.publicContextClosesAt,
          displayTime:
              _timeLabel(echo.publicVerdictAt ?? echo.publicContextClosesAt),
          icon: Icons.balance_rounded,
          color: _publicVerdictColor(echo.publicVerdict),
          chips: [
            _TrailChipData(
              label: _publicVerdictLabel(echo.publicVerdict),
              icon: Icons.verified_outlined,
              color: _publicVerdictColor(echo.publicVerdict),
            ),
          ],
        ),
      );
    }

    if (_hasMeaningfulRecord(
      echo.verifiedRecordStatus,
      echo.verifiedRecordTx,
    )) {
      events.add(
        _ProofTrailEvent(
          title: _recordTitle(
            status: echo.verifiedRecordStatus,
            anchored: context.l('Verification record anchored'),
            pending: context.l('Verification record pending'),
            failed: context.l('Verification record failed'),
          ),
          body: context.l(
            'The community verification outcome is tracked as a separate record.',
          ),
          time: echo.verifiedRecordAt,
          displayTime: _timeLabel(echo.verifiedRecordAt),
          icon: Icons.verified_outlined,
          color: _recordColor(echo.verifiedRecordStatus),
          solanaStatus: echo.verifiedRecordStatus,
          signature: echo.verifiedRecordTx,
          signatureLabel: context.l('Solana verification'),
        ),
      );
    }

    if (echo.bondCount > 0) {
      events.add(
        _ProofTrailEvent(
          title: context.l('Truth bonds attached'),
          body: context.l(
            '{count} bond{suffix} currently stand behind this verified echo.',
            {
              'count': echo.bondCount,
              'suffix': echo.bondCount == 1 ? '' : 's',
            },
          ),
          time: null,
          displayTime: null,
          icon: Icons.workspace_premium_outlined,
          color: AppColors.statusControversial,
          chips: [
            _TrailChipData(
              label: context.l('{count} bonds', {'count': echo.bondCount}),
              icon: Icons.workspace_premium_outlined,
              color: AppColors.statusControversial,
            ),
          ],
        ),
      );
    }

    final ownBond = _ownBond;
    if (ownBond != null) {
      final created = _parseDate(ownBond['created_at']);
      final status = ownBond['bond_status'] as String? ?? 'active';
      final solanaStatus = ownBond['solana_status'] as String? ?? 'pending';
      events.add(
        _ProofTrailEvent(
          title: context.l('Your truth bond'),
          body: context.l(
            'Your account has a {status} bond on this echo.',
            {'status': status.replaceAll('_', ' ')},
          ),
          time: created,
          displayTime: _timeLabel(created),
          icon: Icons.person_pin_circle_outlined,
          color: AppColors.fernGreenDark,
          chips: [
            _TrailChipData(
              label: status,
              icon: Icons.workspace_premium_outlined,
              color: AppColors.fernGreenDark,
            ),
          ],
          solanaStatus: solanaStatus,
          signature: ownBond['mint_tx'] as String?,
          signatureLabel: context.l('Solana bond'),
        ),
      );
    }

    events.sort((a, b) {
      final aTime = a.time;
      final bTime = b.time;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });

    return events;
  }

  String _recordTitle({
    required String status,
    required String anchored,
    required String pending,
    required String failed,
  }) {
    return switch (status) {
      'anchored' => anchored,
      'failed' => failed,
      _ => pending,
    };
  }

  Color _recordColor(String status) {
    return switch (status) {
      'anchored' => AppColors.fernGreenDark,
      'failed' => AppColors.sunsetCoralDark,
      'recording' => AppColors.statusControversial,
      _ => AppColors.textTertiary,
    };
  }

  String _proofBody(String type, Map<String, dynamic> user) {
    final username = user['username'] as String? ?? 'unknown';
    return context.l('@{username} attached {type} evidence.', {
      'username': username,
      'type': _proofTypeLabel(type).toLowerCase(),
    });
  }

  String _contextBody(String stance, Map<String, dynamic> user) {
    final username = user['username'] as String? ?? 'unknown';
    return stance == 'support'
        ? context.l('@{username} supported the echo with public context.', {
            'username': username,
          })
        : context.l('@{username} challenged the echo with public context.', {
            'username': username,
          });
  }

  String _verdictBody(EchoEntity echo) {
    final support = echo.supportCount;
    final challenge = echo.challengeCount;
    return context.l(
      'Decision used {support} support and {challenge} challenge context points.',
      {'support': support, 'challenge': challenge},
    );
  }

  String? _firstMediaUrl(Map<String, dynamic> row) {
    final media = (row['media_urls'] as List?)?.cast<String>() ?? const [];
    return media.isEmpty ? null : media.first;
  }

  IconData _proofIcon(String type) {
    return switch (type) {
      'image' => Icons.image_outlined,
      'document' => Icons.description_outlined,
      'url' => Icons.link_outlined,
      _ => Icons.attach_file_outlined,
    };
  }

  String _proofTypeLabel(String type) {
    return switch (type) {
      'image' => context.l('Image'),
      'document' => context.l('Document'),
      'url' => context.l('Link'),
      _ => context.l('Proof'),
    };
  }

  String? _timeLabel(DateTime? time) {
    if (time == null) return null;
    return Formatters.timeAgo(time);
  }

  String _publicVerdictLabel(String verdict) => switch (verdict) {
        'supported' => context.l('Supported'),
        'not_supported' => context.l('Not supported'),
        'contested' => context.l('Contested'),
        _ => context.l('Open'),
      };

  Color _publicVerdictColor(String verdict) => switch (verdict) {
        'supported' => AppColors.fernGreenDark,
        'not_supported' => AppColors.sunsetCoralDark,
        'contested' => AppColors.statusControversial,
        _ => AppColors.textTertiary,
      };
}

class _ProofTrailHeader extends StatelessWidget {
  const _ProofTrailHeader({
    required this.echo,
    required this.proofCount,
    required this.contextCount,
  });

  final EchoEntity echo;
  final int proofCount;
  final int contextCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TrailAvatar(echo: echo),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          context.l('Proof trail'),
                          style: AppTypography.textTheme.titleLarge?.copyWith(
                            color: AppColors.charcoal,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TrustBadge(tier: echo.userTrustTier),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '@${echo.username} - ${echo.timeAgo}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          RichTextDisplay(
            text: echo.title.isNotEmpty ? echo.title : echo.content,
            style: AppTypography.textTheme.titleMedium?.copyWith(
              height: 1.25,
              color: AppColors.charcoal,
            ),
            hideUrls: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          ConfidenceBar(confidence: echo.confidenceScore, status: echo.status),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _TrailStat(
                icon: Icons.attach_file_outlined,
                label: context.l('Evidence'),
                value: '$proofCount',
                color: AppColors.fernGreenDark,
              ),
              _TrailStat(
                icon: Icons.forum_outlined,
                label: context.l('Context'),
                value: '$contextCount',
                color: AppColors.charcoal,
              ),
              _TrailStat(
                icon: Icons.thumb_up_alt_outlined,
                label: context.l('Support'),
                value: '${echo.supportCount}',
                color: AppColors.fernGreenDark,
              ),
              _TrailStat(
                icon: Icons.report_problem_outlined,
                label: context.l('Challenge'),
                value: '${echo.challengeCount}',
                color: AppColors.sunsetCoralDark,
              ),
              _TrailStat(
                icon: Icons.workspace_premium_outlined,
                label: context.l('Bonds'),
                value: '${echo.bondCount}',
                color: AppColors.statusControversial,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrailAvatar extends StatelessWidget {
  const _TrailAvatar({required this.echo});

  final EchoEntity echo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: echo.userIsVerified
              ? AppColors.fernGreen
              : AppColors.borderSubtle,
          width: 1.4,
        ),
      ),
      child: CircleAvatar(
        backgroundColor: AppColors.softSand,
        backgroundImage:
            echo.userAvatarUrl == null || echo.userAvatarUrl!.isEmpty
                ? null
                : CachedNetworkImageProvider(echo.userAvatarUrl!),
        child: echo.userAvatarUrl == null || echo.userAvatarUrl!.isEmpty
            ? const Icon(
                Icons.person_outline_rounded,
                color: AppColors.textTertiary,
              )
            : null,
      ),
    );
  }
}

class _TrailStat extends StatelessWidget {
  const _TrailStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTypography.textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedTrailItem extends StatelessWidget {
  const _AnimatedTrailItem({
    required this.controller,
    required this.index,
    required this.child,
  });

  final AnimationController controller;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.055).clamp(0.0, 0.62).toDouble();
    final animation = CurvedAnimation(
      parent: controller,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );

    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }
}

class _ProofTrailEventTile extends StatelessWidget {
  const _ProofTrailEventTile({
    required this.event,
    required this.isLast,
  });

  final _ProofTrailEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: event.color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: event.color.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(event.icon, size: 18, color: event.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.borderSubtle,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.borderSubtle),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.charcoal.withValues(alpha: 0.035),
                      blurRadius: 14,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: AppTypography.textTheme.titleSmall?.copyWith(
                              color: AppColors.charcoal,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (event.displayTime != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            event.displayTime!,
                            style: AppTypography.textTheme.labelSmall?.copyWith(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      event.body,
                      style: AppTypography.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (event.mediaUrl != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _TrailMediaPreview(url: event.mediaUrl!),
                    ],
                    if (event.content != null &&
                        event.content!.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      RichTextDisplay(
                        text: event.content!.trim(),
                        style: AppTypography.textTheme.bodySmall?.copyWith(
                          color: AppColors.charcoal,
                          height: 1.38,
                        ),
                        hideUrls: false,
                      ),
                    ],
                    if (event.chips.isNotEmpty ||
                        event.solanaStatus != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final chip in event.chips)
                            _TrailChip(data: chip),
                          if (event.solanaStatus != null)
                            SolanaStatusChip(
                              status: event.solanaStatus!,
                              signature: event.signature,
                              label: event.signatureLabel ?? 'Solana record',
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailMediaPreview extends StatelessWidget {
  const _TrailMediaPreview({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: CachedNetworkImage(
        imageUrl: url,
        width: double.infinity,
        height: 128,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          height: 128,
          color: AppColors.softSand,
        ),
        errorWidget: (_, __, ___) => Container(
          height: 68,
          color: AppColors.softSand,
          alignment: Alignment.center,
          child: const Icon(
            Icons.broken_image_outlined,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _TrailChip extends StatelessWidget {
  const _TrailChip({required this.data});

  final _TrailChipData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: data.color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: 13, color: data.color),
          const SizedBox(width: 5),
          Text(
            data.label,
            style: AppTypography.textTheme.labelSmall?.copyWith(
              color: data.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofTrailEmptyState extends StatelessWidget {
  const _ProofTrailEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.fernGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: const Icon(
              Icons.timeline_rounded,
              color: AppColors.fernGreenDark,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l('No proof trail yet'),
                  style: AppTypography.textTheme.titleSmall?.copyWith(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l(
                    'This echo is published, but no evidence, public context, verification record, or bond has been added yet.',
                  ),
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
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

class _ProofTrailLoading extends StatelessWidget {
  const _ProofTrailLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: const [
        SizedBox(height: 42),
        EchoLogoLoader(label: 'Loading proof trail'),
      ],
    );
  }
}

class _ProofTrailError extends StatelessWidget {
  const _ProofTrailError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: AppColors.sunsetCoralDark,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofTrailEvent {
  const _ProofTrailEvent({
    required this.title,
    required this.body,
    required this.icon,
    required this.color,
    this.time,
    this.displayTime,
    this.content,
    this.mediaUrl,
    this.chips = const [],
    this.solanaStatus,
    this.signature,
    this.signatureLabel,
  });

  final String title;
  final String body;
  final DateTime? time;
  final String? displayTime;
  final IconData icon;
  final Color color;
  final String? content;
  final String? mediaUrl;
  final List<_TrailChipData> chips;
  final String? solanaStatus;
  final String? signature;
  final String? signatureLabel;
}

class _TrailChipData {
  const _TrailChipData({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}
