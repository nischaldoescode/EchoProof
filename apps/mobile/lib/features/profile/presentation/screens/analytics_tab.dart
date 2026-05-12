// Analytics tab — Pro users only.
// Shows real-time post and account stats with animated cards.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/localization/app_copy.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key, required this.userId});
  final String userId;

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
    // Refresh every 30 seconds.
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
            'challenge_count, reply_count, bond_count, status, created_at, media_urls',
          )
          .eq('user_id', widget.userId)
          .order('trust_score', ascending: false)
          .limit(20);

      final profile = await client
          .from('users_public')
          .select(
              'echo_count, proof_count, trust_score, follower_count, following_count, trust_tier')
          .eq('id', widget.userId)
          .maybeSingle();

      final echoList = List<Map<String, dynamic>>.from(echoes as List);

      int totalSupport = 0,
          totalChallenge = 0,
          totalReplies = 0,
          totalBonds = 0;
      var totalConfidence = 0.0;
      var mediaEchoes = 0;
      var verifiedEchoes = 0;
      var pendingEchoes = 0;
      var disputedEchoes = 0;
      for (final e in echoList) {
        totalSupport += (e['support_count'] as num?)?.toInt() ?? 0;
        totalChallenge += (e['challenge_count'] as num?)?.toInt() ?? 0;
        totalReplies += (e['reply_count'] as num?)?.toInt() ?? 0;
        totalBonds += (e['bond_count'] as num?)?.toInt() ?? 0;
        totalConfidence += (e['confidence_score'] as num?)?.toDouble() ?? 0;
        final media = e['media_urls'];
        if (media is List && media.isNotEmpty) mediaEchoes++;
        final status = (e['status'] as String? ?? '').toLowerCase();
        if (status.contains('verified')) {
          verifiedEchoes++;
        } else if (status.contains('challenge') || status.contains('dispute')) {
          disputedEchoes++;
        } else {
          pendingEchoes++;
        }
      }
      final totalReactions = totalSupport + totalChallenge;
      final totalEngagements = totalReactions + totalReplies + totalBonds;

      setState(() {
        _stats = {
          ...?profile,
          'total_support': totalSupport,
          'total_challenge': totalChallenge,
          'total_replies': totalReplies,
          'total_bonds': totalBonds,
          'total_engagements': totalEngagements,
          'support_ratio':
              totalReactions == 0 ? 0.0 : totalSupport / totalReactions,
          'avg_confidence':
              echoList.isEmpty ? 0.0 : totalConfidence / echoList.length,
          'media_echoes': mediaEchoes,
          'verified_echoes': verifiedEchoes,
          'pending_echoes': pendingEchoes,
          'disputed_echoes': disputedEchoes,
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

    return RefreshIndicator(
      color: AppColors.fernGreen,
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _AnalyticsHero(stats: stats),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(label: context.l('Account Overview')),
          const SizedBox(height: AppSpacing.md),
          _StatsGrid(stats: stats),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(label: context.l('Engagement Summary')),
          const SizedBox(height: AppSpacing.md),
          _EngagementRow(
            totalSupport: (stats['total_support'] as num?)?.toInt() ?? 0,
            totalChallenge: (stats['total_challenge'] as num?)?.toInt() ?? 0,
            totalReplies: (stats['total_replies'] as num?)?.toInt() ?? 0,
            totalBonds: (stats['total_bonds'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(height: AppSpacing.md),
          _StatusMixCard(stats: stats),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(label: context.l('Top Echoes by Trust Score')),
          const SizedBox(height: AppSpacing.md),
          ..._topEchoes.asMap().entries.map((e) => _TopEchoCard(
                echo: e.value,
                rank: e.key + 1,
              )),
          const SizedBox(height: 80),
        ],
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

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.6,
      children: items.map((item) => _StatCard(stat: item)).toList(),
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
    final support = (echo['support_count'] as num?)?.toInt() ?? 0;
    final challenge = (echo['challenge_count'] as num?)?.toInt() ?? 0;

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
