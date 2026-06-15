// analytics tab pro users only
// shows real-time post and account stats with animated cards

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/shimmer_loader.dart';

class ProfileAnalyticsScreen extends StatefulWidget {
  const ProfileAnalyticsScreen({super.key});

  @override
  State<ProfileAnalyticsScreen> createState() => _ProfileAnalyticsScreenState();
}

class _ProfileAnalyticsScreenState extends State<ProfileAnalyticsScreen> {
  bool _checking = true;
  bool _isPro = false;
  String? _userId;
  String? _message;

  @override
  void initState() {
    super.initState();
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    setState(() {
      _checking = true;
      _message = null;
    });

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final res = await client.functions.invoke('check-subscription');
      final data = res.data as Map<String, dynamic>?;
      final serverPro = data?['is_pro'] as bool? ?? false;
      final expiresAt = DateTime.tryParse(data?['expires_at'] as String? ?? '');

      final profile = await client
          .from('users_public')
          .select('is_pro, pro_expires_at, pro_plan')
          .eq('id', user.id)
          .maybeSingle();

      final dbPro = profile?['is_pro'] as bool? ?? false;
      final dbExpiresAt =
          DateTime.tryParse(profile?['pro_expires_at'] as String? ?? '');
      final now = DateTime.now().toUtc();
      final serverActive = expiresAt == null || expiresAt.toUtc().isAfter(now);
      final dbActive = dbExpiresAt == null || dbExpiresAt.toUtc().isAfter(now);
      final allowed = serverPro && dbPro && serverActive && dbActive;

      if (!mounted) return;
      setState(() {
        _userId = user.id;
        _isPro = allowed;
        _checking = false;
        _message = allowed
            ? null
            : context.l('Analytics are available with EchoProof Pro.');
      });
    } catch (e) {
      AppLogger.warn('analytics access check failed $e');
      if (!mounted) return;
      setState(() {
        _userId = user.id;
        _isPro = false;
        _checking = false;
        _message = context.l('Could not verify Pro access. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          context.l('Analytics'),
          style: AppTypography.textTheme.titleMedium,
        ),
      ),
      body: SafeArea(
        top: false,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _checking
              ? EchoLogoLoader(
                  key: const ValueKey('checking'),
                  label: context.l('Checking Pro access'),
                )
              : _isPro && _userId != null
                  ? AnalyticsTab(
                      key: ValueKey('analytics_$_userId'),
                      userId: _userId!,
                      isStandalone: true,
                    )
                  : _AnalyticsLockedState(
                      key: const ValueKey('locked'),
                      message: _message,
                      bottomPadding: bottom,
                      onRetry: _verifyAccess,
                      onUpgrade: () => context.push('/subscribe'),
                    ),
        ),
      ),
    );
  }
}

class _AnalyticsLockedState extends StatelessWidget {
  const _AnalyticsLockedState({
    super.key,
    required this.message,
    required this.bottomPadding,
    required this.onRetry,
    required this.onUpgrade,
  });

  final String? message;
  final double bottomPadding;
  final VoidCallback onRetry;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + bottomPadding,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
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
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: AppColors.fernGreenLight,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        color: AppColors.fernGreenDark,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      context.l('Pro analytics'),
                      style: AppTypography.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      message ??
                          context.l(
                            'Upgrade to view private profile analytics.',
                          ),
                      textAlign: TextAlign.center,
                      style: AppTypography.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onRetry,
                            child: Text(context.l('Retry')),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onUpgrade,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.charcoal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            child: Text(context.l('View Pro')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({
    super.key,
    required this.userId,
    this.isStandalone = false,
  });
  final String userId;
  final bool isStandalone;

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _topEchoes = [];
  bool _isLoading = true;
  Timer? _refreshTimer;
  RealtimeChannel? _channel;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadStats();
    // refresh every 30 seconds
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _loadStats());
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadStats() async {
    try {
      final client = Supabase.instance.client;
      final echoes = await client
          .from('echoes')
          .select(
            'id, title, trust_score, confidence_score, support_count, '
            'challenge_count, context_support_count, context_challenge_count, '
            'context_score, public_verdict, reply_count, bond_count, status, '
            'created_at, media_urls',
          )
          .eq('user_id', widget.userId)
          .order('trust_score', ascending: false)
          .limit(100);

      final profile = await client
          .from('users_public')
          .select(
              'echo_count, proof_count, trust_score, follower_count, following_count, trust_tier')
          .eq('id', widget.userId)
          .maybeSingle();

      final echoList = List<Map<String, dynamic>>.from(echoes as List);
      final now = DateTime.now().toUtc();
      final recentCutoff = now.subtract(const Duration(days: 7));
      final previousCutoff = now.subtract(const Duration(days: 14));

      int totalSupport = 0,
          totalChallenge = 0,
          totalReplies = 0,
          totalBonds = 0;
      var recentEchoes = 0;
      var previousEchoes = 0;
      var recentEngagements = 0;
      var previousEngagements = 0;
      var totalConfidence = 0.0;
      var mediaEchoes = 0;
      var verifiedEchoes = 0;
      var pendingEchoes = 0;
      var disputedEchoes = 0;
      var supportedByContext = 0;
      var notSupportedByContext = 0;
      var contestedByContext = 0;
      for (final e in echoList) {
        final contextSupport = (e['context_support_count'] as num?)?.toInt() ??
            (e['support_count'] as num?)?.toInt() ??
            0;
        final contextChallenge =
            (e['context_challenge_count'] as num?)?.toInt() ??
                (e['challenge_count'] as num?)?.toInt() ??
                0;
        totalSupport += contextSupport;
        totalChallenge += contextChallenge;
        final replies = (e['reply_count'] as num?)?.toInt() ?? 0;
        final bonds = (e['bond_count'] as num?)?.toInt() ?? 0;
        totalReplies += replies;
        totalBonds += bonds;
        final engagement = contextSupport + contextChallenge + replies + bonds;
        final createdAt =
            DateTime.tryParse(e['created_at'] as String? ?? '')?.toUtc();
        if (createdAt != null && createdAt.isAfter(recentCutoff)) {
          recentEchoes++;
          recentEngagements += engagement;
        } else if (createdAt != null && createdAt.isAfter(previousCutoff)) {
          previousEchoes++;
          previousEngagements += engagement;
        }
        totalConfidence += (e['confidence_score'] as num?)?.toDouble() ?? 0;
        final media = e['media_urls'];
        if (media is List && media.isNotEmpty) mediaEchoes++;
        final publicVerdict =
            (e['public_verdict'] as String? ?? 'open').toLowerCase();
        if (publicVerdict == 'supported') {
          supportedByContext++;
        } else if (publicVerdict == 'not_supported') {
          notSupportedByContext++;
        } else if (publicVerdict == 'contested') {
          contestedByContext++;
        }
        final status = (e['status'] as String? ?? '').toLowerCase();
        if (status.contains('verified')) {
          verifiedEchoes++;
        } else if (status.contains('challenge') ||
            status.contains('dispute') ||
            publicVerdict == 'not_supported') {
          disputedEchoes++;
        } else {
          pendingEchoes++;
        }
      }
      final totalReactions = totalSupport + totalChallenge;
      final totalEngagements = totalReactions + totalReplies + totalBonds;
      final engagementDelta = previousEngagements == 0
          ? (recentEngagements > 0 ? 1.0 : 0.0)
          : (recentEngagements - previousEngagements) / previousEngagements;
      final proofCount = (profile?['proof_count'] as num?)?.toInt() ?? 0;
      final echoCount = (profile?['echo_count'] as num?)?.toInt() ??
          (echoList.isEmpty ? 0 : echoList.length);
      final proofRatio = echoCount == 0 ? 0.0 : proofCount / echoCount;
      final challengeRate =
          totalReactions == 0 ? 0.0 : totalChallenge / totalReactions;

      setState(() {
        _stats = {
          ...?profile,
          'total_support': totalSupport,
          'total_challenge': totalChallenge,
          'total_replies': totalReplies,
          'total_bonds': totalBonds,
          'total_engagements': totalEngagements,
          'recent_echoes': recentEchoes,
          'previous_echoes': previousEchoes,
          'recent_engagements': recentEngagements,
          'previous_engagements': previousEngagements,
          'engagement_delta': engagementDelta,
          'engagement_per_echo':
              echoList.isEmpty ? 0.0 : totalEngagements / echoList.length,
          'challenge_rate': challengeRate,
          'proof_ratio': proofRatio,
          'support_ratio':
              totalReactions == 0 ? 0.0 : totalSupport / totalReactions,
          'avg_confidence':
              echoList.isEmpty ? 0.0 : totalConfidence / echoList.length,
          'media_echoes': mediaEchoes,
          'verified_echoes': verifiedEchoes,
          'pending_echoes': pendingEchoes,
          'disputed_echoes': disputedEchoes,
          'supported_by_context': supportedByContext,
          'not_supported_by_context': notSupportedByContext,
          'contested_by_context': contestedByContext,
        };
        _topEchoes = echoList.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _subscribeRealtime() {
    final client = Supabase.instance.client;
    _channel = client
        .channel('analytics_${widget.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'echoes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (_) => _loadStats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users_public',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.userId,
          ),
          callback: (_) => _loadStats(),
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.fernGreen),
      );
    }

    final stats = _stats ?? {};
    final bottom = MediaQuery.paddingOf(context).bottom;

    return RefreshIndicator(
      color: AppColors.fernGreen,
      onRefresh: _loadStats,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal =
              constraints.maxWidth >= 720 ? AppSpacing.xl : AppSpacing.lg;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontal,
              AppSpacing.lg,
              horizontal,
              AppSpacing.xl + bottom,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AnalyticsHero(stats: stats),
                      const SizedBox(height: AppSpacing.lg),
                      _MomentumCard(stats: stats),
                      const SizedBox(height: AppSpacing.md),
                      _InsightActionCard(stats: stats),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionHeader(label: context.l('Account Overview')),
                      const SizedBox(height: AppSpacing.md),
                      _StatsGrid(stats: stats),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionHeader(label: context.l('Engagement Summary')),
                      const SizedBox(height: AppSpacing.md),
                      _EngagementRow(
                        totalSupport:
                            (stats['total_support'] as num?)?.toInt() ?? 0,
                        totalChallenge:
                            (stats['total_challenge'] as num?)?.toInt() ?? 0,
                        totalReplies:
                            (stats['total_replies'] as num?)?.toInt() ?? 0,
                        totalBonds:
                            (stats['total_bonds'] as num?)?.toInt() ?? 0,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PublicContextMixCard(stats: stats),
                      const SizedBox(height: AppSpacing.md),
                      _StatusMixCard(stats: stats),
                      const SizedBox(height: AppSpacing.xl),
                      _SectionHeader(
                        label: context.l('Top Echoes by Trust Score'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ..._topEchoes.asMap().entries.map((e) => _TopEchoCard(
                            echo: e.value,
                            rank: e.key + 1,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnalyticsHero extends StatelessWidget {
  const _AnalyticsHero({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final trust = (stats['trust_score'] as num?)?.toInt() ?? 0;
    final avgConfidence = (stats['avg_confidence'] as num?)?.toDouble() ?? 0;
    final engagements = (stats['total_engagements'] as num?)?.toInt() ?? 0;
    final supportRatio = (stats['support_ratio'] as num?)?.toDouble() ?? 0;
    final tier = (stats['trust_tier'] as String? ?? 'building')
        .replaceAll('_', ' ')
        .toUpperCase();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
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
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.charcoal.withValues(alpha: 0.12),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.fernGreen.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    tier,
                    style: GoogleFonts.josefinSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.fernGreenLight,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.insights_rounded,
                  color: AppColors.fernGreenLight,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              '$trust',
              style: GoogleFonts.josefinSans(
                fontSize: 42,
                fontWeight: FontWeight.w800,
                color: AppColors.white,
              ),
            ),
            Text(
              context.l('trust score'),
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                color: AppColors.white.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                _HeroMetric(
                  label: context.l('Engagements'),
                  value: '$engagements',
                ),
                _HeroMetric(
                  label: context.l('Avg confidence'),
                  value: '${avgConfidence.round()}%',
                ),
                _HeroMetric(
                  label: context.l('Supportive'),
                  value: '${(supportRatio * 100).round()}%',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.josefinSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 10,
              color: AppColors.white.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentumCard extends StatelessWidget {
  const _MomentumCard({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final recent = (stats['recent_engagements'] as num?)?.toInt() ?? 0;
    final previous = (stats['previous_engagements'] as num?)?.toInt() ?? 0;
    final delta = (stats['engagement_delta'] as num?)?.toDouble() ?? 0;
    final perEcho = (stats['engagement_per_echo'] as num?)?.toDouble() ?? 0;
    final recentEchoes = (stats['recent_echoes'] as num?)?.toInt() ?? 0;
    final isUp = delta >= 0;
    final capped = delta.abs().clamp(0.0, 1.0).toDouble();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  color: isUp ? AppColors.fernGreen : AppColors.sunsetCoral,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    context.l('7-day momentum'),
                    style: GoogleFonts.josefinSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                  ),
                ),
                Text(
                  '${isUp ? '+' : '-'}${(delta.abs() * 100).round()}%',
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color:
                        isUp ? AppColors.fernGreenDark : AppColors.sunsetCoral,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: capped == 0 ? 0.04 : capped,
                minHeight: 8,
                backgroundColor: AppColors.surfaceSecondary,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isUp ? AppColors.fernGreen : AppColors.sunsetCoral,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _TinyMetric(
                    label: context.l('This week'),
                    value: '$recent',
                  ),
                ),
                Expanded(
                  child: _TinyMetric(
                    label: context.l('Last week'),
                    value: '$previous',
                  ),
                ),
                Expanded(
                  child: _TinyMetric(
                    label: context.l('Per echo'),
                    value: perEcho.toStringAsFixed(1),
                  ),
                ),
                Expanded(
                  child: _TinyMetric(
                    label: context.l('New echoes'),
                    value: '$recentEchoes',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightActionCard extends StatelessWidget {
  const _InsightActionCard({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final supportRatio = (stats['support_ratio'] as num?)?.toDouble() ?? 0;
    final challengeRate = (stats['challenge_rate'] as num?)?.toDouble() ?? 0;
    final proofRatio = (stats['proof_ratio'] as num?)?.toDouble() ?? 0;
    final avgConfidence = (stats['avg_confidence'] as num?)?.toDouble() ?? 0;
    final recentEchoes = (stats['recent_echoes'] as num?)?.toInt() ?? 0;

    final title = recentEchoes == 0
        ? context.l('Post once this week')
        : challengeRate > 0.45
            ? context.l('Reduce challenge pressure')
            : avgConfidence < 60
                ? context.l('Raise confidence')
                : supportRatio > 0.7
                    ? context.l('Lean into trusted topics')
                    : context.l('Strengthen your next echo');
    final body = recentEchoes == 0
        ? context.l('Fresh activity keeps your trust graph alive.')
        : challengeRate > 0.45
            ? context.l('Add clearer source context before claims spread.')
            : avgConfidence < 60
                ? context.l('Use specific evidence and shorter wording.')
                : supportRatio > 0.7
                    ? context.l('Your audience is responding with support.')
                    : context.l('Proof coverage and clarity move the score.');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.fernGreen.withValues(alpha: 0.18),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 520;
          final metrics = [
            _TinyMetric(
              label: context.l('Support'),
              value: '${(supportRatio * 100).round()}%',
            ),
            _TinyMetric(
              label: context.l('Challenge'),
              value: '${(challengeRate * 100).round()}%',
            ),
            _TinyMetric(
              label: context.l('Proof cover'),
              value: '${(proofRatio * 100).round()}%',
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.auto_graph_rounded,
                    color: AppColors.fernGreenDark,
                    size: 21,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.josefinSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.charcoal,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          body,
                          style: GoogleFonts.josefinSans(
                            fontSize: 12,
                            height: 1.3,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (stacked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: metrics
                      .map(
                        (metric) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: metric,
                        ),
                      )
                      .toList(),
                )
              else
                Row(
                  children: metrics
                      .map((metric) => Expanded(child: metric))
                      .toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TinyMetric extends StatelessWidget {
  const _TinyMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      margin: const EdgeInsets.only(right: AppSpacing.xs),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.josefinSans(
              fontSize: 10,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: AppColors.fernGreen,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.josefinSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.charcoal,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final items = [
      _GridStat(
          context.l('Trust Score'),
          '${(stats['trust_score'] as num?)?.toInt() ?? 0}',
          Icons.shield_outlined,
          AppColors.fernGreen),
      _GridStat(
          context.l('Echoes'),
          '${(stats['echo_count'] as num?)?.toInt() ?? 0}',
          Icons.record_voice_over_outlined,
          AppColors.charcoal),
      _GridStat(
          context.l('Followers'),
          '${(stats['follower_count'] as num?)?.toInt() ?? 0}',
          Icons.people_outline,
          AppColors.fernGreen),
      _GridStat(
          context.l('Following'),
          '${(stats['following_count'] as num?)?.toInt() ?? 0}',
          Icons.person_add_outlined,
          AppColors.textSecondary),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 4 : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: columns == 4 ? 1.25 : 1.6,
          children: items.map((item) => _StatCard(stat: item)).toList(),
        );
      },
    );
  }
}

class _GridStat {
  const _GridStat(this.label, this.value, this.icon, this.color);
  final String label, value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatefulWidget {
  const _StatCard({required this.stat});
  final _GridStat stat;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
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
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(widget.stat.icon, size: 20, color: widget.stat.color),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.stat.value,
                  style: GoogleFonts.josefinSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
                Text(
                  widget.stat.label,
                  style: GoogleFonts.josefinSans(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EngagementRow extends StatelessWidget {
  const _EngagementRow({
    required this.totalSupport,
    required this.totalChallenge,
    required this.totalReplies,
    required this.totalBonds,
  });
  final int totalSupport, totalChallenge, totalReplies, totalBonds;

  @override
  Widget build(BuildContext context) {
    final total = totalSupport + totalChallenge;
    final supportRatio = total > 0 ? totalSupport / total : 0.5;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _EngagementChip(
                icon: Icons.thumb_up_outlined,
                label: context.l('Support'),
                value: totalSupport,
                color: AppColors.fernGreen,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EngagementChip(
                icon: Icons.thumb_down_outlined,
                label: context.l('Challenge'),
                value: totalChallenge,
                color: AppColors.sunsetCoral,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EngagementChip(
                icon: Icons.chat_bubble_outline,
                label: context.l('Replies'),
                value: totalReplies,
                color: AppColors.charcoal,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EngagementChip(
                icon: Icons.link_outlined,
                label: context.l('Bonds'),
                value: totalBonds,
                color: const Color(0xFF9C6FDE),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              context.l('Support ratio'),
              style: GoogleFonts.josefinSans(
                  fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: supportRatio,
                backgroundColor: AppColors.sunsetCoral.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.fernGreen),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l('{percent}% supportive', {
                'percent': (supportRatio * 100).round(),
              }),
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                color: AppColors.fernGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EngagementChip extends StatelessWidget {
  const _EngagementChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(
            '$value',
            style: GoogleFonts.josefinSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.josefinSans(
                fontSize: 9, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _StatusMixCard extends StatelessWidget {
  const _StatusMixCard({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final verified = (stats['verified_echoes'] as num?)?.toInt() ?? 0;
    final pending = (stats['pending_echoes'] as num?)?.toInt() ?? 0;
    final disputed = (stats['disputed_echoes'] as num?)?.toInt() ?? 0;
    final media = (stats['media_echoes'] as num?)?.toInt() ?? 0;
    final total = verified + pending + disputed;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l('Content mix'),
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),
              const Spacer(),
              Icon(
                media > 0 ? Icons.perm_media_outlined : Icons.article_outlined,
                size: 17,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                context.l('{count} media echoes', {'count': media}),
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Row(
              children: [
                _MixSegment(
                  flex: verified,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.fernGreen,
                ),
                _MixSegment(
                  flex: pending,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.statusUnderReview,
                ),
                _MixSegment(
                  flex: disputed,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.sunsetCoral,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Legend(
                  label: context.l('Verified'),
                  value: verified,
                  color: AppColors.fernGreen),
              _Legend(
                  label: context.l('Pending'),
                  value: pending,
                  color: AppColors.statusUnderReview),
              _Legend(
                  label: context.l('Disputed'),
                  value: disputed,
                  color: AppColors.sunsetCoral),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublicContextMixCard extends StatelessWidget {
  const _PublicContextMixCard({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final supported = (stats['supported_by_context'] as num?)?.toInt() ?? 0;
    final notSupported =
        (stats['not_supported_by_context'] as num?)?.toInt() ?? 0;
    final contested = (stats['contested_by_context'] as num?)?.toInt() ?? 0;
    final open = ((stats['echo_count'] as num?)?.toInt() ?? 0) -
        supported -
        notSupported -
        contested;
    final safeOpen = open < 0 ? 0 : open;
    final total = supported + notSupported + contested + safeOpen;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.l('Public context verdicts'),
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.groups_2_outlined,
                size: 17,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Row(
              children: [
                _MixSegment(
                  flex: supported,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.fernGreen,
                ),
                _MixSegment(
                  flex: notSupported,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.sunsetCoral,
                ),
                _MixSegment(
                  flex: contested,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.statusControversial,
                ),
                _MixSegment(
                  flex: safeOpen,
                  fallbackFlex: total == 0 ? 1 : 0,
                  color: AppColors.borderMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _Legend(
                label: context.l('Supported'),
                value: supported,
                color: AppColors.fernGreen,
              ),
              _Legend(
                label: context.l('Not supported'),
                value: notSupported,
                color: AppColors.sunsetCoral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _Legend(
                label: context.l('Contested'),
                value: contested,
                color: AppColors.statusControversial,
              ),
              _Legend(
                label: context.l('Open'),
                value: safeOpen,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MixSegment extends StatelessWidget {
  const _MixSegment({
    required this.flex,
    required this.fallbackFlex,
    required this.color,
  });
  final int flex;
  final int fallbackFlex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final effectiveFlex = flex > 0 ? flex : fallbackFlex;
    if (effectiveFlex == 0) return const SizedBox.shrink();
    return Expanded(
      flex: effectiveFlex,
      child: Container(height: 9, color: color),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '$label $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopEchoCard extends StatelessWidget {
  const _TopEchoCard({required this.echo, required this.rank});
  final Map<String, dynamic> echo;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final title = echo['title'] as String? ?? context.l('Untitled');
    final trust = (echo['trust_score'] as num?)?.toInt() ?? 0;
    final confidence = (echo['confidence_score'] as num?)?.toDouble() ?? 0.0;
    final support = (echo['context_support_count'] as num?)?.toInt() ??
        (echo['support_count'] as num?)?.toInt() ??
        0;
    final challenge = (echo['context_challenge_count'] as num?)?.toInt() ??
        (echo['challenge_count'] as num?)?.toInt() ??
        0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rank <= 3 ? AppColors.fernGreenLight : AppColors.softSand,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color:
                      rank <= 3 ? AppColors.fernGreen : AppColors.textTertiary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.charcoal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  context.l(
                    '{confidence}% confidence · {support} ↑ {challenge} ↓',
                    {
                      'confidence': confidence.toStringAsFixed(0),
                      'support': support,
                      'challenge': challenge,
                    },
                  ),
                  style: GoogleFonts.josefinSans(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: trust >= 0
                  ? AppColors.fernGreenLight
                  : AppColors.sunsetCoralLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              trust >= 0 ? '+$trust' : '$trust',
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: trust >= 0
                    ? AppColors.fernGreenDark
                    : AppColors.sunsetCoralDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
