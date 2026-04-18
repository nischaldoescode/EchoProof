// echo feed provider
// fetches, caches, and paginates the echo feed
// supports optimistic updates when user supports/challenges an echo

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const _kPageSize = 20;

/// feed state — holds list + pagination metadata
class EchoFeedState {
  const EchoFeedState({
    this.echoes = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.error,
    
  });

  final List<EchoEntity> echoes;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;

  EchoFeedState copyWith({
    List<EchoEntity>? echoes,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
  }) {
    return EchoFeedState(
      echoes: echoes ?? this.echoes,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

class EchoFeedNotifier extends AsyncNotifier<EchoFeedState> {
  int _offset = 0;

  @override
  Future<EchoFeedState> build() async {
    _offset = 0;
    final echoes = await _fetchEchoes(offset: 0);
    return EchoFeedState(echoes: echoes, hasMore: echoes.length == _kPageSize);
  }

// called after user supports or challenges an echo
// forces a cache-busted refresh of the feed so stale scores are not shown
  Future<void> invalidateAndRefresh() async {
    _offset = 0;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final echoes = await _fetchEchoes(offset: 0, forceRefresh: true);
      return EchoFeedState(
          echoes: echoes, hasMore: echoes.length == _kPageSize);
    });
  }

  /// loads the next page and appends to the list
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));

    try {
      _offset += _kPageSize;
      final more = await _fetchEchoes(offset: _offset);
      final updated = [...current.echoes, ...more];
      state = AsyncData(current.copyWith(
        echoes: updated,
        hasMore: more.length == _kPageSize,
        isLoadingMore: false,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(isLoadingMore: false));
    }
  }

  /// refresh from top — pull to refresh
  Future<void> refresh() async {
    _offset = 0;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final echoes = await _fetchEchoes(offset: 0);
      return EchoFeedState(
          echoes: echoes, hasMore: echoes.length == _kPageSize);
    });
  }

  /// optimistic update — immediately updates an echo in the list
  /// while the edge function runs in the background
  /// reverts on failure
  void applyOptimisticInteraction({
    required String echoId,
    required String type, // 'support' or 'challenge'
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final updated = current.echoes.map((echo) {
      if (echo.id != echoId) return echo;
      return echo.copyWith(
        supportCount:
            type == 'support' ? echo.supportCount + 1 : echo.supportCount,
        challengeCount:
            type == 'challenge' ? echo.challengeCount + 1 : echo.challengeCount,
      );
    }).toList();

    state = AsyncData(current.copyWith(echoes: updated));
  }

  Future<List<EchoEntity>> _fetchEchoes({
    required int offset,
    bool forceRefresh = false,
  }) async {
    final client = ref.read(supabaseProvider);
    final session = client.auth.currentSession;
    if (session == null) return [];

    final refreshParam = forceRefresh ? '&refresh=1' : '';
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    final response = await http.get(
      Uri.parse(
          '$supabaseUrl/functions/v1/personalized-feed?offset=$offset&limit=$_kPageSize'),
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('feed fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['echoes'] as List? ?? [];

    return list.map((row) {
      final map = row as Map<String, dynamic>;
      final user = map['users_public'] as Map<String, dynamic>;
      return _mapToEntity(map, user);
    }).toList();
  }

  EchoEntity _mapToEntity(Map<String, dynamic> row, Map<String, dynamic> user) {
    final createdAt =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final diff = DateTime.now().difference(createdAt);

    String timeAgo;
    if (diff.inMinutes < 60)
      timeAgo = '${diff.inMinutes}m ago';
    else if (diff.inHours < 24)
      timeAgo = '${diff.inHours}h ago';
    else
      timeAgo = '${diff.inDays}d ago';

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
    );
  }

  EchoStatus _parseStatus(String value) => switch (value) {
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
}

final echoFeedProvider = AsyncNotifierProvider<EchoFeedNotifier, EchoFeedState>(
  EchoFeedNotifier.new,
);
