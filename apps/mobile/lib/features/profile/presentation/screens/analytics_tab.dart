// Analytics tab — Pro users only.
// Shows real-time post and account stats with animated cards.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({required this.userId});
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
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadStats());
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
            'challenge_count, reply_count, bond_count, status, created_at',
          )
          .eq('user_id', widget.userId)
          .order('trust_score', ascending: false)
          .limit(20);

      final profile = await client
          .from('users_public')
          .select('echo_count, proof_count, trust_score, follower_count, following_count, trust_tier')
          .eq('id', widget.userId)
          .maybeSingle();

      final echoList = List<Map<String, dynamic>>.from(echoes as List);

      int totalSupport = 0, totalChallenge = 0, totalReplies = 0, totalBonds = 0;
      for (final e in echoList) {
        totalSupport += (e['support_count'] as num?)?.toInt() ?? 0;
        totalChallenge += (e['challenge_count'] as num?)?.toInt() ?? 0;
        totalReplies += (e['reply_count'] as num?)?.toInt() ?? 0;
        totalBonds += (e['bond_count'] as num?)?.toInt() ?? 0;
      }

      setState(() {
        _stats = {
          ...?profile,
          'total_support': totalSupport,
          'total_challenge': totalChallenge,
          'total_replies': totalReplies,
          'total_bonds': totalBonds,
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
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.fernGreen),
      );
    }

    return RefreshIndicator(
      color: AppColors.fernGreen,
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _SectionHeader(label: 'Account Overview'),
          const SizedBox(height: AppSpacing.md),
          _StatsGrid(stats: _stats ?? {}),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(label: 'Engagement Summary'),
          const SizedBox(height: AppSpacing.md),
          _EngagementRow(
            totalSupport: (_stats?['total_support'] as num?)?.toInt() ?? 0,
            totalChallenge: (_stats?['total_challenge'] as num?)?.toInt() ?? 0,
            totalReplies: (_stats?['total_replies'] as num?)?.toInt() ?? 0,
            totalBonds: (_stats?['total_bonds'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(label: 'Top Echoes by Trust Score'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, color: AppColors.fernGreen,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(2))),
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
      _GridStat('Trust Score', '${(stats['trust_score'] as num?)?.toInt() ?? 0}', Icons.shield_outlined, AppColors.fernGreen),
      _GridStat('Echoes', '${(stats['echo_count'] as num?)?.toInt() ?? 0}', Icons.record_voice_over_outlined, AppColors.charcoal),
      _GridStat('Followers', '${(stats['follower_count'] as num?)?.toInt() ?? 0}', Icons.people_outline, AppColors.fernGreen),
      _GridStat('Following', '${(stats['following_count'] as num?)?.toInt() ?? 0}', Icons.person_add_outlined, AppColors.textSecondary),
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
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
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
                label: 'Support',
                value: totalSupport,
                color: AppColors.fernGreen,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EngagementChip(
                icon: Icons.thumb_down_outlined,
                label: 'Challenge',
                value: totalChallenge,
                color: AppColors.sunsetCoral,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EngagementChip(
                icon: Icons.chat_bubble_outline,
                label: 'Replies',
                value: totalReplies,
                color: AppColors.charcoal,
              ),
              const SizedBox(width: AppSpacing.sm),
              _EngagementChip(
                icon: Icons.link_outlined,
                label: 'Bonds',
                value: totalBonds,
                color: const Color(0xFF9C6FDE),
              ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Support ratio',
              style: GoogleFonts.josefinSans(fontSize: 11, color: AppColors.textTertiary),
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
              '${(supportRatio * 100).round()}% supportive',
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
            style: GoogleFonts.josefinSans(fontSize: 9, color: AppColors.textTertiary),
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
    final title = echo['title'] as String? ?? 'Untitled';
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
                  color: rank <= 3 ? AppColors.fernGreen : AppColors.textTertiary,
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
                  '${confidence.toStringAsFixed(0)}% confidence · $support ↑ $challenge ↓',
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
              color: trust >= 0 ? AppColors.fernGreenLight : AppColors.sunsetCoralLight,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              trust >= 0 ? '+$trust' : '$trust',
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: trust >= 0 ? AppColors.fernGreenDark : AppColors.sunsetCoralDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}