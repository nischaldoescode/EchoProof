// profile screen
// shows reputation card, user echoes, bond history
// uses plain StatefulWidget with supabase — no riverpod

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../auth/presentation/services/auth_service.dart';
import '../../../echo/domain/entities/echo_entity.dart';
import '../../../echo/domain/entities/echo_status.dart';
import '../../../echo/presentation/widgets/echo_card.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../../shared/widgets/trust_tier_label.dart';
import '../../../../shared/widgets/verified_badge.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/logger.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List<EchoEntity> _echoes = [];
  int _settledBonds = 0;
  int _contestedBonds = 0;
  int _activeBonds = 0;
  bool _isIdentityVerified = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final results = await Future.wait([
        client
            .from('users_public')
            .select(
              'username, avatar_url, trust_tier, trust_score, echo_count, '
              'proof_count, wallet_address',
            )
            .eq('id', userId)
            .single(),
        client
            .from('echoes')
            .select(
              'id, title, content, category, status, trust_score, '
              'confidence_score, controversy_score, support_count, '
              'challenge_count, created_at',
            )
            .eq('user_id', userId)
            .not('status', 'in', '("hidden","rejected")')
            .order('created_at', ascending: false)
            .limit(20),
        client.from('truth_bonds').select('bond_status').eq('user_id', userId),
        client
            .from('users_private')
            .select('is_identity_verified')
            .eq('id', userId)
            .maybeSingle(),
      ]);

      final profile = results[0] as Map<String, dynamic>;
      final echoes = results[1] as List;
      final bonds = results[2] as List;
      final priv = results[3] as Map<String, dynamic>?;

      final echoEntities = echoes.map((row) {
        final r = row as Map<String, dynamic>;
        final created = DateTime.tryParse(r['created_at'] as String? ?? '') ??
            DateTime.now();
        return EchoEntity(
          id: r['id'] as String,
          title: r['title'] as String? ?? '',
          content: r['content'] as String,
          username: profile['username'] as String,
          userTrustTier: profile['trust_tier'] as String? ?? 'unverified',
          userIsVerified: priv?['is_identity_verified'] as bool? ?? false,
          userAvatarUrl: profile['avatar_url'] as String?,
          category: EchoCategory.fromString(r['category'] as String),
          status: _parseStatus(r['status'] as String),
          confidenceScore: (r['confidence_score'] as num?)?.toDouble() ?? 0.0,
          trustScore: (r['trust_score'] as num?)?.toInt() ?? 0,
          controversyScore: (r['controversy_score'] as num?)?.toDouble() ?? 0.0,
          supportCount: (r['support_count'] as num?)?.toInt() ?? 0,
          challengeCount: (r['challenge_count'] as num?)?.toInt() ?? 0,
          timeAgo: Formatters.timeAgo(created),
        );
      }).toList();

      setState(() {
        _profile = profile;
        _echoes = echoEntities;
        _settledBonds =
            bonds.where((b) => b['bond_status'] == 'settled').length;
        _contestedBonds =
            bonds.where((b) => b['bond_status'] == 'contested').length;
        _activeBonds = bonds.where((b) => b['bond_status'] == 'active').length;
        _isIdentityVerified = priv?['is_identity_verified'] as bool? ?? false;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.error('profile: load failed', e);
      setState(() => _isLoading = false);
    }
  }

  EchoStatus _parseStatus(String v) => switch (v) {
        'verified' => EchoStatus.verified,
        'disputed' => EchoStatus.disputed,
        'controversial' => EchoStatus.controversial,
        'active' => EchoStatus.active,
        _ => EchoStatus.pendingVerification,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Profile', style: AppTypography.textTheme.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_outlined, size: 20),
            onPressed: () {
              context.read<AuthService>().signOut();
              context.go('/login');
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: EchoCardShimmer(),
            )
          : _profile == null
              ? Center(
                  child: Text(
                    'could not load profile',
                    style: AppTypography.textTheme.bodyMedium,
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.fernGreen,
                  onRefresh: _loadProfile,
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [
                      _ReputationCard(
                        profile: _profile!,
                        isIdentityVerified: _isIdentityVerified,
                        settledBonds: _settledBonds,
                        contestedBonds: _contestedBonds,
                        activeBonds: _activeBonds,
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // identity verification prompt
                      if (!_isIdentityVerified)
                        GestureDetector(
                          onTap: () => context.push('/verify-identity'),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.fernGreenLight,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusMd,
                              ),
                              border: Border.all(
                                color: AppColors.fernGreen.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.shield_outlined,
                                  size: 18,
                                  color: AppColors.fernGreen,
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'Verify your identity to increase your trust weight',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.fernGreenDark,
                                      fontFamily: AppTypography.fontFamily,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: AppColors.fernGreen,
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (!_isIdentityVerified)
                        const SizedBox(height: AppSpacing.lg),

                      Text(
                        'Echoes',
                        style: AppTypography.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      if (_echoes.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xl,
                          ),
                          child: Text(
                            'No echoes yet',
                            style: AppTypography.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ),

                      ..._echoes.map((echo) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: EchoCard(
                              echo: echo,
                              onTap: () =>
                                  context.push('/feed/echo/${echo.id}'),
                            ),
                          )),
                    ],
                  ),
                ),
    );
  }
}

class _ReputationCard extends StatelessWidget {
  const _ReputationCard({
    required this.profile,
    required this.isIdentityVerified,
    required this.settledBonds,
    required this.contestedBonds,
    required this.activeBonds,
  });

  final Map<String, dynamic> profile;
  final bool isIdentityVerified;
  final int settledBonds;
  final int contestedBonds;
  final int activeBonds;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile['avatar_url'] as String?;
    final username = profile['username'] as String? ?? '';
    final trustTier = profile['trust_tier'] as String? ?? 'unverified';
    final trustScore = (profile['trust_score'] as num?)?.toInt() ?? 0;
    final echoCount = (profile['echo_count'] as num?)?.toInt() ?? 0;
    final proofCount = (profile['proof_count'] as num?)?.toInt() ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: AppSpacing.avatarSizeMd / 2,
                backgroundColor: AppColors.softSand,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? const Icon(
                        Icons.person_outline,
                        size: 22,
                        color: AppColors.textTertiary,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '@$username',
                          style: AppTypography.textTheme.titleMedium,
                        ),
                        if (isIdentityVerified) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const VerifiedBadge(),
                        ],
                      ],
                    ),
                    TrustTierLabel(tier: trustTier),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              _Stat(label: 'Echoes', value: echoCount),
              _Divider(),
              _Stat(label: 'Proofs', value: proofCount),
              _Divider(),
              _Stat(label: 'Score', value: trustScore),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _BondStat(
                label: 'Settled',
                value: settledBonds,
                color: AppColors.fernGreen,
              ),
              const SizedBox(width: AppSpacing.md),
              _BondStat(
                label: 'Active',
                value: activeBonds,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: AppSpacing.md),
              _BondStat(
                label: 'Contested',
                value: contestedBonds,
                color: AppColors.sunsetCoral,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: AppTypography.textTheme.headlineSmall),
          Text(label, style: AppTypography.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _BondStat extends StatelessWidget {
  const _BondStat({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
            fontFamily: AppTypography.fontFamily,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: AppColors.borderSubtle,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}
