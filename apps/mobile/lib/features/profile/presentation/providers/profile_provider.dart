// profile provider
// fetches a user's public profile and their echoes + bond history

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../echo/domain/entities/echo_entity.dart';
import '../../../echo/domain/entities/echo_status.dart';

class ProfileState {
  const ProfileState({
    this.username = '',
    this.avatarUrl,
    this.trustTier = 'unverified',
    this.trustScore = 0,
    this.echoCount = 0,
    this.proofCount = 0,
    this.walletAddress,
    this.isIdentityVerified = false,
    this.echoes = const [],
    this.settledBonds = 0,
    this.contestedBonds = 0,
    this.activeBonds = 0,
    this.isLoading = false,
    this.error,
  });

  final String  username;
  final String? avatarUrl;
  final String  trustTier;
  final int     trustScore;
  final int     echoCount;
  final int     proofCount;
  final String? walletAddress;
  final bool    isIdentityVerified;
  final List<EchoEntity> echoes;
  final int     settledBonds;
  final int     contestedBonds;
  final int     activeBonds;
  final bool    isLoading;
  final String? error;

  ProfileState copyWith({
    String?  username,
    String?  avatarUrl,
    String?  trustTier,
    int?     trustScore,
    int?     echoCount,
    int?     proofCount,
    String?  walletAddress,
    bool?    isIdentityVerified,
    List<EchoEntity>? echoes,
    int?     settledBonds,
    int?     contestedBonds,
    int?     activeBonds,
    bool?    isLoading,
    String?  error,
  }) {
    return ProfileState(
      username:            username            ?? this.username,
      avatarUrl:           avatarUrl           ?? this.avatarUrl,
      trustTier:           trustTier           ?? this.trustTier,
      trustScore:          trustScore          ?? this.trustScore,
      echoCount:           echoCount           ?? this.echoCount,
      proofCount:          proofCount          ?? this.proofCount,
      walletAddress:       walletAddress       ?? this.walletAddress,
      isIdentityVerified:  isIdentityVerified  ?? this.isIdentityVerified,
      echoes:              echoes              ?? this.echoes,
      settledBonds:        settledBonds        ?? this.settledBonds,
      contestedBonds:      contestedBonds      ?? this.contestedBonds,
      activeBonds:         activeBonds         ?? this.activeBonds,
      isLoading:           isLoading           ?? this.isLoading,
      error:               error,
    );
  }
}

class ProfileNotifier extends AsyncNotifier<ProfileState> {
  @override
  Future<ProfileState> build() async {
    return _fetchProfile(ref.read(currentUserIdProvider));
  }

  Future<ProfileState> _fetchProfile(String userId) async {
    final client = ref.read(supabaseProvider);

    final profile = await client
        .from('users_public')
        .select('username, avatar_url, trust_tier, trust_score, echo_count, proof_count, wallet_address')
        .eq('id', userId)
        .single();

    final echoes = await client
        .from('echoes')
        .select('id, title, content, category, status, trust_score, confidence_score, controversy_score, support_count, challenge_count, created_at')
        .eq('user_id', userId)
        .not('status', 'in', '("hidden","rejected")')
        .order('created_at', ascending: false)
        .limit(20);

    final bonds = await client
        .from('truth_bonds')
        .select('bond_status')
        .eq('user_id', userId);

    final bondList = List<Map<String, dynamic>>.from(bonds);
    final settled   = bondList.where((b) => b['bond_status'] == 'settled').length;
    final contested = bondList.where((b) => b['bond_status'] == 'contested').length;
    final active    = bondList.where((b) => b['bond_status'] == 'active').length;

    final privateData = await client
        .from('users_private')
        .select('is_identity_verified')
        .eq('id', userId)
        .maybeSingle();

    final echoEntities = (echoes as List).map((row) {
      final created = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
      final diff    = DateTime.now().difference(created);
      final timeAgo = diff.inHours < 1
          ? '${diff.inMinutes}m ago'
          : diff.inHours < 24
              ? '${diff.inHours}h ago'
              : '${diff.inDays}d ago';

      return EchoEntity(
        id:             row['id'] as String,
        title:          row['title'] as String? ?? '',
        content:        row['content'] as String,
        username:       profile['username'] as String,
        userTrustTier:  profile['trust_tier'] as String? ?? 'unverified',
        userIsVerified: privateData?['is_identity_verified'] as bool? ?? false,
        userAvatarUrl:  profile['avatar_url'] as String?,
        category:       EchoCategory.fromString(row['category'] as String),
        status:         _parseStatus(row['status'] as String),
        confidenceScore:  (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
        trustScore:       (row['trust_score'] as num?)?.toInt() ?? 0,
        controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
        supportCount:     (row['support_count'] as num?)?.toInt() ?? 0,
        challengeCount:   (row['challenge_count'] as num?)?.toInt() ?? 0,
        timeAgo:          timeAgo,
      );
    }).toList();

    return ProfileState(
      username:           profile['username'] as String,
      avatarUrl:          profile['avatar_url'] as String?,
      trustTier:          profile['trust_tier'] as String? ?? 'unverified',
      trustScore:         (profile['trust_score'] as num?)?.toInt() ?? 0,
      echoCount:          (profile['echo_count'] as num?)?.toInt() ?? 0,
      proofCount:         (profile['proof_count'] as num?)?.toInt() ?? 0,
      walletAddress:      profile['wallet_address'] as String?,
      isIdentityVerified: privateData?['is_identity_verified'] as bool? ?? false,
      echoes:             echoEntities,
      settledBonds:       settled,
      contestedBonds:     contested,
      activeBonds:        active,
    );
  }

  EchoStatus _parseStatus(String v) => switch (v) {
    'verified'     => EchoStatus.verified,
    'disputed'     => EchoStatus.disputed,
    'controversial' => EchoStatus.controversial,
    'active'       => EchoStatus.active,
    _              => EchoStatus.pendingVerification,
  };
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, ProfileState>(
  ProfileNotifier.new,
);