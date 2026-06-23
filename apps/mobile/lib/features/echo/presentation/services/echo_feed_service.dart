// echo feed service
// fetches and manages the personalized feed
// replaces: echo_feed_provider.dart (riverpod version)
// screens listen via context.watch<echofeedservice>()

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/services/app_analytics_service.dart';

const _kPageSize = 20;

enum FeedLoadState { idle, loading, loadingMore, error }

class _FeedPage {
  const _FeedPage({
    required this.echoes,
    required this.hasMore,
    this.nextCursor,
    this.sessionSeed,
  });

  final List<EchoEntity> echoes;
  final bool hasMore;
  final String? nextCursor;
  final String? sessionSeed;

  _FeedPage copyWith({
    List<EchoEntity>? echoes,
    bool? hasMore,
    String? nextCursor,
    String? sessionSeed,
  }) {
    return _FeedPage(
      echoes: echoes ?? this.echoes,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      sessionSeed: sessionSeed ?? this.sessionSeed,
    );
  }
}

class _FeedVisibilityGuards {
  const _FeedVisibilityGuards({
    required this.userId,
    required this.hiddenEchoIds,
    required this.hiddenAuthorIds,
  });

  final String? userId;
  final Set<String> hiddenEchoIds;
  final Set<String> hiddenAuthorIds;
}

class EchoFeedService extends ChangeNotifier {
  List<EchoEntity> _echoes = [];
  List<EchoEntity> get echoes => List.unmodifiable(_echoes);

  Set<String> _followingIds = {};
  Set<String> get followingIds => Set.unmodifiable(_followingIds);

  FeedLoadState _loadState = FeedLoadState.idle;
  FeedLoadState get loadState => _loadState;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  int _pendingNewEchoCount = 0;
  int get pendingNewEchoCount => _pendingNewEchoCount;

  String? _error;
  String? get error => _error;

  String? _nextCursor;
  String? _sessionSeed;
  int _fallbackOffset = 0;
  RealtimeChannel? _feedChannel;
  DateTime? _realtimeStartedAt;

  bool get isLoading => _loadState == FeedLoadState.loading;
  bool get isLoadingMore => _loadState == FeedLoadState.loadingMore;

  void removeEcho(String echoId) {
    final next = _echoes.where((echo) => echo.id != echoId).toList();
    if (next.length == _echoes.length) return;
    _echoes = next;
    notifyListeners();
  }

  Future<_FeedPage> _fetchFallback() async {
    AppLogger.info('feed: running fallback direct DB query');
    final echoes = await _fetchRecencyPage(
      offset: _fallbackOffset,
      limit: _kPageSize,
    );
    return _FeedPage(echoes: echoes, hasMore: echoes.length == _kPageSize);
  }

  Future<_FeedPage> _fetchPageWithTopUp({
    String? cursor,
    String? sessionSeed,
    bool forceRefresh = false,
    Set<String> excludeIds = const {},
  }) async {
    final rankedPage = await _fetchPage(
      cursor: cursor,
      sessionSeed: sessionSeed,
      forceRefresh: forceRefresh,
    );
    return _topUpShortPage(rankedPage, excludeIds: excludeIds);
  }

  /// fills a short ranked page with safe recency items before the ui sees it.
  ///
  /// the edge ranker can return fewer rows than requested when personalization,
  /// feedback, privacy, or public verdict filters remove candidates. without
  /// this top-up the feed may look like it only has two posts even when more
  /// public posts exist. duplicates are removed before decoration.
  Future<_FeedPage> _topUpShortPage(
    _FeedPage rankedPage, {
    Set<String> excludeIds = const {},
  }) async {
    if (rankedPage.echoes.length >= _kPageSize) return rankedPage;

    final existingIds = {
      ...excludeIds,
      for (final echo in rankedPage.echoes) echo.id,
    };
    final missingCount = _kPageSize - rankedPage.echoes.length;
    final topUp = await _fetchRecencyPage(
      offset: 0,
      limit: missingCount,
      excludeIds: existingIds,
    );

    if (topUp.isEmpty) return rankedPage;
    AppLogger.info(
      'feed: topped up ranked page with ${topUp.length} recency echoes',
    );
    return rankedPage.copyWith(echoes: [...rankedPage.echoes, ...topUp]);
  }

  Future<List<EchoEntity>> _fetchRecencyPage({
    required int offset,
    required int limit,
    Set<String> excludeIds = const {},
  }) async {
    final client = Supabase.instance.client;

    try {
      final guards = await _loadFeedVisibilityGuards(client);
      final fetchLimit = math.min(60, math.max(_kPageSize, limit * 3));

      final rows = await client
          .from('echoes')
          .select('''
            id, title, content, category, category_detail, status, version,
            user_id, media_urls, reply_count, proof_count, bond_count,
            trust_score, confidence_score, controversy_score, report_score,
            support_count, challenge_count, context_support_count,
            context_challenge_count, context_score, public_verdict,
            public_verdict_at, public_context_closes_at,
            public_context_min_count, public_context_decision_reason, created_at,
            created_record_tx, created_record_at, solana_status, solana_error,
            verified_record_tx, verified_record_at,
            verified_record_status, verified_record_error,
            users_public!echoes_user_id_fkey!inner(username, display_name, avatar_url, trust_tier, is_pro, is_public)
          ''')
          .not('status', 'in', '("hidden","rejected")')
          .eq('users_public.is_public', true)
          .order('created_at', ascending: false)
          .range(offset, offset + fetchLimit - 1);

      AppLogger.info('feed: fallback returned ${(rows as List).length} echoes');

      return (rows as List)
          .where((row) {
            final r = row as Map<String, dynamic>;
            final echoId = r['id'] as String? ?? '';
            final authorId = r['user_id'] as String? ?? '';
            final verdict = r['public_verdict'] as String? ?? 'open';
            final isOwnEcho =
                guards.userId != null && authorId == guards.userId;
            return !excludeIds.contains(echoId) &&
                !guards.hiddenEchoIds.contains(echoId) &&
                !guards.hiddenAuthorIds.contains(authorId) &&
                (isOwnEcho ||
                    (verdict != 'not_supported' &&
                        verdict != 'insufficient_context'));
          })
          .map((row) {
            final r = row as Map<String, dynamic>;
            final user = r['users_public'] as Map<String, dynamic>;
            return _mapToEntity(r, user);
          })
          .take(limit)
          .toList();
    } catch (e) {
      AppLogger.error('feed: fallback query failed: $e');
      rethrow;
    }
  }

  Future<_FeedVisibilityGuards> _loadFeedVisibilityGuards(
    SupabaseClient client,
  ) async {
    final userId = client.auth.currentUser?.id;
    final hiddenEchoIds = <String>{};
    final hiddenAuthorIds = <String>{};

    if (userId == null) {
      return _FeedVisibilityGuards(
        userId: null,
        hiddenEchoIds: hiddenEchoIds,
        hiddenAuthorIds: hiddenAuthorIds,
      );
    }

    final results = await Future.wait([
      client
          .from('user_feed_feedback')
          .select('echo_id, author_id, feedback_type')
          .eq('user_id', userId)
          .filter(
            'feedback_type',
            'in',
            '("not_interested","report","block_author")',
          ),
      client.from('user_blocks').select('blocked_id').eq('blocker_id', userId),
    ]);
    for (final row in List<Map<String, dynamic>>.from(results[0] as List)) {
      final echoId = row['echo_id'] as String?;
      if (echoId != null) hiddenEchoIds.add(echoId);
      if (row['feedback_type'] == 'block_author') {
        final authorId = row['author_id'] as String?;
        if (authorId != null) hiddenAuthorIds.add(authorId);
      }
    }
    for (final row in List<Map<String, dynamic>>.from(results[1] as List)) {
      final blockedId = row['blocked_id'] as String?;
      if (blockedId != null) hiddenAuthorIds.add(blockedId);
    }

    return _FeedVisibilityGuards(
      userId: userId,
      hiddenEchoIds: hiddenEchoIds,
      hiddenAuthorIds: hiddenAuthorIds,
    );
  }

  // loads the first page call this when the feed screen mounts
  Future<void> loadFeed() async {
    if (_loadState == FeedLoadState.loading) return;
    _nextCursor = null;
    _sessionSeed = null;
    _fallbackOffset = 0;
    _loadState = FeedLoadState.loading;
    _error = null;
    notifyListeners();

    AppLogger.info('feed: loadFeed called');

    try {
      await _refreshFollowingIds();
      final page = await _fetchPageWithTopUp();
      final results = await _decorateFeed(
        page.echoes,
        includeFollowedLikes: true,
      );
      _echoes = results;
      _nextCursor = page.nextCursor;
      _sessionSeed = page.sessionSeed;
      _hasMore = page.hasMore && _nextCursor != null;
      _pendingNewEchoCount = 0;
      _realtimeStartedAt = DateTime.now().toUtc();
      _loadState = FeedLoadState.idle;
      unawaited(
        AppAnalyticsService.instance.logEvent(
          'feed_loaded',
          parameters: {'result_count': results.length},
        ),
      );
      AppLogger.info(
        'feed: loaded ${results.length} echoes from edge function',
      );
    } catch (e) {
      AppLogger.warn('feed: edge function failed ($e), trying fallback');
      try {
        final fallbackPage = await _fetchFallback();
        final fallback = await _decorateFeed(
          fallbackPage.echoes,
          includeFollowedLikes: true,
        );
        _echoes = fallback;
        _hasMore = fallbackPage.hasMore;
        _loadState = FeedLoadState.idle;
        AppLogger.info('feed: fallback loaded ${fallback.length} echoes');
      } catch (e2) {
        AppLogger.error(
          'feed: both edge function and fallback failed. edge=$e fallback=$e2',
        );
        _loadState = FeedLoadState.error;
        _error = 'could not load feed';
      }
    }
    notifyListeners();
  }

  // loads next page and appends call when user scrolls near bottom
  Future<void> loadMore() async {
    if (_loadState == FeedLoadState.loadingMore || !_hasMore) return;
    final cursor = _nextCursor;
    if (cursor == null) {
      _hasMore = false;
      notifyListeners();
      return;
    }
    _loadState = FeedLoadState.loadingMore;
    notifyListeners();

    try {
      if (_followingIds.isEmpty) {
        await _refreshFollowingIds();
      }
      final existingIds = _echoes.map((echo) => echo.id).toSet();
      final page = await _fetchPageWithTopUp(
        cursor: cursor,
        sessionSeed: _sessionSeed,
        excludeIds: existingIds,
      );
      final more = await _decorateFeed(page.echoes);
      _echoes = _mergeUniqueEchoes(_echoes, more);
      _nextCursor = page.nextCursor;
      _sessionSeed = page.sessionSeed ?? _sessionSeed;
      _hasMore = page.hasMore && _nextCursor != null;
      unawaited(
        AppAnalyticsService.instance.logEvent(
          'feed_page_loaded',
          parameters: {'result_count': more.length},
        ),
      );
    } catch (e) {
      AppLogger.error('feed: cursor load more failed', e);
    }

    _loadState = FeedLoadState.idle;
    notifyListeners();
  }

  // pull to refresh reloads from page 1 with cache bust
  Future<void> refresh() async {
    _nextCursor = null;
    _sessionSeed = null;
    _fallbackOffset = 0;
    _loadState = FeedLoadState.loading;
    _error = null;
    notifyListeners();

    try {
      await _refreshFollowingIds();
      final page = await _fetchPageWithTopUp(forceRefresh: true);
      final results = await _decorateFeed(
        page.echoes,
        includeFollowedLikes: true,
      );
      _echoes = results;
      _nextCursor = page.nextCursor;
      _sessionSeed = page.sessionSeed;
      _hasMore = page.hasMore && _nextCursor != null;
      _pendingNewEchoCount = 0;
      _realtimeStartedAt = DateTime.now().toUtc();
      _loadState = FeedLoadState.idle;
      unawaited(AppAnalyticsService.instance.logEvent('feed_refreshed'));
    } catch (e) {
      _loadState = FeedLoadState.error;
      _error = 'could not refresh feed';
    }
    notifyListeners();
  }

  List<EchoEntity> _mergeUniqueEchoes(
    List<EchoEntity> current,
    List<EchoEntity> incoming,
  ) {
    final seen = current.map((echo) => echo.id).toSet();
    final output = [...current];
    for (final echo in incoming) {
      if (seen.add(echo.id)) output.add(echo);
    }
    return output;
  }

  /// listens only for a deferred refresh signal; it never inserts cards while
  /// a reader is scrolling, so the visible feed keeps its position.
  void startRealtime() {
    if (_feedChannel != null) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeStartedAt = DateTime.now().toUtc();
    _feedChannel = Supabase.instance.client
        .channel('home_feed_updates_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'echoes',
          callback: (payload) {
            final row = payload.newRecord;
            final createdAt = DateTime.tryParse(
              row['created_at'] as String? ?? '',
            );
            final startedAt = _realtimeStartedAt;
            if (createdAt == null ||
                startedAt == null ||
                !createdAt.isAfter(startedAt)) {
              return;
            }
            final status = row['status'] as String?;
            if (status == 'hidden' || status == 'rejected') return;
            _pendingNewEchoCount = (_pendingNewEchoCount + 1)
                .clamp(0, 99)
                .toInt();
            notifyListeners();
          },
        )
        .subscribe();
  }

  Future<void> refreshPendingNewEchoes() async {
    if (_pendingNewEchoCount == 0) return;
    await refresh();
    if (_loadState != FeedLoadState.error) {
      _pendingNewEchoCount = 0;
      _realtimeStartedAt = DateTime.now().toUtc();
      notifyListeners();
    }
  }

  Future<void> stopRealtime() async {
    final channel = _feedChannel;
    _feedChannel = null;
    _realtimeStartedAt = null;
    _pendingNewEchoCount = 0;
    if (channel != null) {
      await Supabase.instance.client.removeChannel(channel);
    }
  }

  // optimistic update updates local state immediately before server confirms
  void applyOptimisticInteraction({
    required String echoId,
    required String type,
  }) {
    _echoes = _echoes.map((echo) {
      if (echo.id != echoId) return echo;
      return echo.copyWith(
        supportCount: type == 'support'
            ? echo.supportCount + 1
            : echo.supportCount,
        challengeCount: type == 'challenge'
            ? echo.challengeCount + 1
            : echo.challengeCount,
      );
    }).toList();
    notifyListeners();
  }

  // reverts optimistic update if the server call failed
  void revertOptimisticInteraction({
    required String echoId,
    required String type,
  }) {
    _echoes = _echoes.map((echo) {
      if (echo.id != echoId) return echo;
      return echo.copyWith(
        supportCount: type == 'support'
            ? echo.supportCount - 1
            : echo.supportCount,
        challengeCount: type == 'challenge'
            ? echo.challengeCount - 1
            : echo.challengeCount,
      );
    }).toList();
    notifyListeners();
  }

  // updates a specific echo's scores from the server response
  // called after on-interaction edge function returns
  void updateEchoScores({
    required String echoId,
    required int trustScore,
    required double confidenceScore,
    required int supportCount,
    required int challengeCount,
    required EchoStatus status,
  }) {
    _echoes = _echoes.map((echo) {
      if (echo.id != echoId) return echo;
      return echo.copyWith(
        trustScore: trustScore,
        confidenceScore: confidenceScore,
        supportCount: supportCount,
        challengeCount: challengeCount,
        status: status,
      );
    }).toList();
    notifyListeners();
  }

  Future<_FeedPage> _fetchPage({
    String? cursor,
    String? sessionSeed,
    bool forceRefresh = false,
  }) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) {
      return const _FeedPage(echoes: [], hasMore: false);
    }

    final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    final anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
    final refreshParam = forceRefresh ? '&refresh=1' : '';
    final cursorParam = cursor == null
        ? ''
        : '&cursor=${Uri.encodeQueryComponent(cursor)}';
    final seedParam = sessionSeed == null
        ? ''
        : '&seed=${Uri.encodeQueryComponent(sessionSeed)}';

    final response = await http.get(
      Uri.parse(
        '$supabaseUrl/functions/v1/personalized-feed'
        '?limit=$_kPageSize$cursorParam$seedParam$refreshParam',
      ),
      headers: {
        if (anonKey.isNotEmpty) 'apikey': anonKey,
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('feed fetch failed: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['echoes'] as List? ?? [];
    final echoes = list.map((row) {
      final map = row as Map<String, dynamic>;
      final user = map['users_public'] as Map<String, dynamic>;
      return _mapToEntity(map, user);
    }).toList();
    return _FeedPage(
      echoes: echoes,
      hasMore: data['has_more'] as bool? ?? data['hasMore'] as bool? ?? false,
      nextCursor: data['next_cursor'] as String?,
      sessionSeed: data['session_seed'] as String?,
    );
  }

  Future<List<EchoEntity>> _decorateFeed(
    List<EchoEntity> echoes, {
    bool includeFollowedLikes = false,
  }) async {
    if (echoes.isEmpty) return echoes;

    var decorated = echoes;
    if (includeFollowedLikes) {
      decorated = await _injectFollowingAuthoredEchoes(decorated);
      decorated = await _injectFollowedLikedEchoes(decorated);
    }
    decorated = await _attachSocialContext(decorated);
    decorated = await _attachContextPreviews(decorated);
    decorated = await _attachReplyPreviews(decorated);
    return decorated;
  }

  Future<void> _refreshFollowingIds() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        _followingIds = {};
        return;
      }

      final rows = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', userId);
      final next = List<Map<String, dynamic>>.from(rows as List)
          .map((row) => row['following_id'] as String?)
          .whereType<String>()
          .toSet();
      if (!setEquals(_followingIds, next)) {
        _followingIds = next;
      }
    } catch (e) {
      AppLogger.warn('feed: following graph skipped $e');
    }
  }

  Future<List<EchoEntity>> _injectFollowingAuthoredEchoes(
    List<EchoEntity> echoes,
  ) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || _followingIds.isEmpty) return echoes;

      final existingIds = echoes.map((echo) => echo.id).toSet();
      final hiddenEchoIds = <String>{};
      final hiddenAuthorIds = <String>{};
      final hiddenResults = await Future.wait([
        client
            .from('user_feed_feedback')
            .select('echo_id, author_id, feedback_type')
            .eq('user_id', userId)
            .filter(
              'feedback_type',
              'in',
              '("not_interested","report","block_author")',
            ),
        client
            .from('user_blocks')
            .select('blocked_id')
            .eq('blocker_id', userId),
      ]);

      for (final row in List<Map<String, dynamic>>.from(
        hiddenResults[0] as List,
      )) {
        final echoId = row['echo_id'] as String?;
        if (echoId != null) hiddenEchoIds.add(echoId);
        if (row['feedback_type'] == 'block_author') {
          final authorId = row['author_id'] as String?;
          if (authorId != null) hiddenAuthorIds.add(authorId);
        }
      }
      for (final row in List<Map<String, dynamic>>.from(
        hiddenResults[1] as List,
      )) {
        final blockedId = row['blocked_id'] as String?;
        if (blockedId != null) hiddenAuthorIds.add(blockedId);
      }

      final followedIds = _followingIds.join(',');
      final rows = await client
          .from('echoes')
          .select('''
            id, title, content, category, category_detail, status, version,
            user_id, media_urls, reply_count, proof_count, bond_count,
            trust_score, confidence_score, controversy_score, report_score,
            support_count, challenge_count, context_support_count,
            context_challenge_count, context_score, public_verdict,
            public_verdict_at, public_context_closes_at,
            public_context_min_count, public_context_decision_reason, created_at,
            created_record_tx, created_record_at, solana_status, solana_error,
            verified_record_tx, verified_record_at,
            verified_record_status, verified_record_error,
            users_public!echoes_user_id_fkey!inner(username, display_name, avatar_url, trust_tier, is_pro, is_public)
          ''')
          .filter('user_id', 'in', '($followedIds)')
          .not('status', 'in', '("hidden","rejected")')
          .not(
            'public_verdict',
            'in',
            '("not_supported","insufficient_context")',
          )
          .order('created_at', ascending: false)
          .limit(16);

      final candidates = <EchoEntity>[];
      for (final raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final echoId = row['id'] as String? ?? '';
        final authorId = row['user_id'] as String? ?? '';
        if (existingIds.contains(echoId) ||
            hiddenEchoIds.contains(echoId) ||
            hiddenAuthorIds.contains(authorId)) {
          continue;
        }
        final user = row['users_public'] as Map<String, dynamic>;
        candidates.add(_mapToEntity(row, user));
        if (candidates.length >= 4) break;
      }

      if (candidates.isEmpty) return echoes;

      final output = <EchoEntity>[];
      var addIndex = 0;
      for (var i = 0; i < echoes.length; i++) {
        output.add(echoes[i]);
        final insertionPoint = i == 1 || i == 6 || i == 13;
        if (insertionPoint && addIndex < candidates.length) {
          output.add(candidates[addIndex++]);
        }
      }
      while (addIndex < candidates.length) {
        output.add(candidates[addIndex++]);
      }
      return output;
    } catch (e) {
      AppLogger.warn('feed: following-authored injection skipped $e');
      return echoes;
    }
  }

  Future<List<EchoEntity>> _injectFollowedLikedEchoes(
    List<EchoEntity> echoes,
  ) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null || echoes.length < 4) return echoes;

      final followRows = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', userId);
      final followingIds = List<Map<String, dynamic>>.from(followRows as List)
          .map((row) => row['following_id'] as String?)
          .whereType<String>()
          .toSet();
      if (followingIds.isEmpty) return echoes;

      final hiddenEchoIds = <String>{};
      final hiddenAuthorIds = <String>{};
      final hiddenResults = await Future.wait([
        client
            .from('user_feed_feedback')
            .select('echo_id, author_id, feedback_type')
            .eq('user_id', userId)
            .filter(
              'feedback_type',
              'in',
              '("not_interested","report","block_author")',
            ),
        client
            .from('user_blocks')
            .select('blocked_id')
            .eq('blocker_id', userId),
      ]);
      for (final row in List<Map<String, dynamic>>.from(
        hiddenResults[0] as List,
      )) {
        final echoId = row['echo_id'] as String?;
        if (echoId != null) hiddenEchoIds.add(echoId);
        if (row['feedback_type'] == 'block_author') {
          final authorId = row['author_id'] as String?;
          if (authorId != null) hiddenAuthorIds.add(authorId);
        }
      }
      for (final row in List<Map<String, dynamic>>.from(
        hiddenResults[1] as List,
      )) {
        final blockedId = row['blocked_id'] as String?;
        if (blockedId != null) hiddenAuthorIds.add(blockedId);
      }

      final followedIds = followingIds.join(',');
      final existingIds = echoes.map((echo) => echo.id).toSet();
      final interactionRows = await client
          .from('echo_interactions')
          .select('echo_id, user_id, created_at')
          .filter('user_id', 'in', '($followedIds)')
          .eq('type', 'support')
          .order('created_at', ascending: false)
          .limit(24);

      final candidateIds = <String>[];
      for (final raw in interactionRows as List) {
        final row = raw as Map<String, dynamic>;
        final echoId = row['echo_id'] as String?;
        if (echoId == null || existingIds.contains(echoId)) continue;
        if (hiddenEchoIds.contains(echoId)) continue;
        if (!candidateIds.contains(echoId)) candidateIds.add(echoId);
        if (candidateIds.length >= 8) break;
      }
      if (candidateIds.isEmpty) return echoes;

      final rows = await client
          .from('echoes')
          .select('''
            id, title, content, category, category_detail, status, version,
            user_id, media_urls, reply_count, proof_count, bond_count,
            trust_score, confidence_score, controversy_score, report_score,
            support_count, challenge_count, context_support_count,
            context_challenge_count, context_score, public_verdict,
            public_verdict_at, public_context_closes_at,
            public_context_min_count, public_context_decision_reason, created_at,
            created_record_tx, created_record_at, solana_status, solana_error,
            verified_record_tx, verified_record_at,
            verified_record_status, verified_record_error,
            users_public!echoes_user_id_fkey!inner(username, display_name, avatar_url, trust_tier, is_pro, is_public)
          ''')
          .filter('id', 'in', '(${candidateIds.join(',')})')
          .not('status', 'in', '("hidden","rejected")')
          .eq('users_public.is_public', true);

      final byId = <String, EchoEntity>{};
      for (final raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final user = row['users_public'] as Map<String, dynamic>;
        final entity = _mapToEntity(row, user);
        if (entity.userId == userId) continue;
        if (hiddenAuthorIds.contains(entity.userId)) continue;
        byId[entity.id] = entity;
      }

      final additions = candidateIds
          .map((id) => byId[id])
          .whereType<EchoEntity>()
          .take(2)
          .toList();
      if (additions.isEmpty) return echoes;

      final output = <EchoEntity>[];
      var addIndex = 0;
      for (var i = 0; i < echoes.length; i++) {
        output.add(echoes[i]);
        final insertionPoint = i == 3 || i == 10;
        if (insertionPoint && addIndex < additions.length) {
          output.add(additions[addIndex++]);
        }
      }
      while (addIndex < additions.length && output.length < echoes.length) {
        output.add(additions[addIndex++]);
      }

      return output.take(echoes.length).toList();
    } catch (e) {
      AppLogger.warn('feed: followed-liked injection skipped $e');
      return echoes;
    }
  }

  Future<List<EchoEntity>> _attachSocialContext(List<EchoEntity> echoes) async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return echoes;

      final followRows = await client
          .from('user_follows')
          .select('following_id')
          .eq('follower_id', userId);
      final followingIds = List<Map<String, dynamic>>.from(followRows as List)
          .map((row) => row['following_id'] as String?)
          .whereType<String>()
          .toSet();
      if (followingIds.isEmpty) return echoes;

      final echoIds = echoes.map((echo) => echo.id).join(',');
      final followedIds = followingIds.join(',');
      final rows = await client
          .from('echo_interactions')
          .select('''
            echo_id, user_id, created_at,
            users_public!inner(username, display_name)
          ''')
          .filter('echo_id', 'in', '($echoIds)')
          .filter('user_id', 'in', '($followedIds)')
          .eq('type', 'support')
          .order('created_at', ascending: false)
          .limit(80);

      final byEcho = <String, List<Map<String, dynamic>>>{};
      for (final raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final echoId = row['echo_id'] as String?;
        if (echoId == null) continue;
        byEcho.putIfAbsent(echoId, () => []).add(row);
      }

      return echoes.map((echo) {
        final likers = byEcho[echo.id] ?? const <Map<String, dynamic>>[];
        if (likers.isEmpty) return echo;

        final visible = likers
            .where((row) => row['user_id'] != echo.userId)
            .take(3)
            .toList();
        if (visible.isEmpty) return echo;

        final firstUser = visible.first['users_public'] as Map<String, dynamic>;
        final firstName =
            (firstUser['display_name'] as String?)?.trim().isNotEmpty == true
            ? firstUser['display_name'] as String
            : '@${firstUser['username'] as String? ?? 'someone'}';
        final extra = visible.length - 1;
        final label = extra > 0
            ? 'Liked by $firstName and $extra ${extra == 1 ? 'other' : 'others'} you follow'
            : 'Liked by $firstName';
        return echo.copyWith(socialContext: label);
      }).toList();
    } catch (e) {
      AppLogger.warn('feed: social context skipped $e');
      return echoes;
    }
  }

  Future<List<EchoEntity>> _attachContextPreviews(
    List<EchoEntity> echoes,
  ) async {
    try {
      if (echoes.isEmpty) return echoes;

      final echoIds = echoes.map((echo) => echo.id).join(',');
      final rows = await Supabase.instance.client
          .from('signal_responses')
          .select('''
            id, echo_id, user_id, content, stance, like_count, media_urls, created_at,
            users_public!signal_responses_user_id_fkey(
              id, username, display_name, avatar_url, is_pro
            )
          ''')
          .filter('echo_id', 'in', '($echoIds)')
          .filter('stance', 'in', '("support","challenge")')
          .eq('moderation_status', 'approved')
          .order('like_count', ascending: false)
          .order('created_at', ascending: false)
          .limit(80);

      final byEcho = <String, EchoContextPreview>{};
      for (final raw in rows as List) {
        final row = raw as Map<String, dynamic>;
        final echoId = row['echo_id'] as String?;
        if (echoId == null || byEcho.containsKey(echoId)) continue;
        final user = row['users_public'] as Map<String, dynamic>? ?? {};
        byEcho[echoId] = EchoContextPreview(
          id: row['id'] as String? ?? '',
          content: row['content'] as String? ?? '',
          stance: row['stance'] as String? ?? 'support',
          username: user['username'] as String? ?? 'unknown',
          displayName:
              (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : user['username'] as String? ?? 'unknown',
          userId: row['user_id'] as String? ?? '',
          avatarUrl: user['avatar_url'] as String?,
          userIsPro: user['is_pro'] as bool? ?? false,
          likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
          mediaUrls: (row['media_urls'] as List?)?.cast<String>() ?? const [],
          createdAt: _parseDate(row['created_at']),
        );
      }

      return echoes
          .map((echo) => echo.copyWith(topContext: byEcho[echo.id]))
          .toList();
    } catch (e) {
      AppLogger.warn('feed: context previews skipped $e');
      return echoes;
    }
  }

  Future<List<EchoEntity>> _attachReplyPreviews(List<EchoEntity> echoes) async {
    try {
      final withReplies = echoes.where((echo) => echo.replyCount > 0).toList();
      if (withReplies.isEmpty) return echoes;

      final echoIds = withReplies.map((echo) => echo.id).join(',');
      final rows = await Supabase.instance.client
          .from('echo_replies')
          .select('''
            id, echo_id, user_id, content, parent_reply_id, created_at,
            like_count, child_reply_count,
            users_public!inner(
              id, username, display_name, avatar_url, trust_tier, is_pro
            )
          ''')
          .filter('echo_id', 'in', '($echoIds)')
          .order('created_at', ascending: false)
          .limit(80);

      final rowList = List<Map<String, dynamic>>.from(rows as List);
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final followingIds = <String>{};
      final likedReplyIds = <String>{};
      if (currentUserId != null) {
        final followRows = await Supabase.instance.client
            .from('user_follows')
            .select('following_id')
            .eq('follower_id', currentUserId);
        followingIds.addAll(
          List<Map<String, dynamic>>.from(
            followRows as List,
          ).map((row) => row['following_id'] as String?).whereType<String>(),
        );
      }
      if (currentUserId != null && rowList.isNotEmpty) {
        final replyIds = rowList
            .map((row) => row['id'] as String?)
            .whereType<String>()
            .join(',');
        if (replyIds.isNotEmpty) {
          final likedRows = await Supabase.instance.client
              .from('echo_reply_interactions')
              .select('reply_id')
              .eq('user_id', currentUserId)
              .eq('type', 'like')
              .filter('reply_id', 'in', '($replyIds)');
          likedReplyIds.addAll(
            List<Map<String, dynamic>>.from(
              likedRows as List,
            ).map((row) => row['reply_id'] as String?).whereType<String>(),
          );
        }
      }

      final byEcho = <String, EchoReplyPreview>{};
      for (final preferFollowed in const [true, false]) {
        for (final row in rowList) {
          if (row['parent_reply_id'] != null) continue;
          final echoId = row['echo_id'] as String?;
          if (echoId == null || byEcho.containsKey(echoId)) continue;
          final replyUserId = row['user_id'] as String?;
          final isFromFollowed =
              replyUserId != null && followingIds.contains(replyUserId);
          if (preferFollowed && !isFromFollowed) continue;

          final user = row['users_public'] as Map<String, dynamic>? ?? {};
          final username = user['username'] as String? ?? 'unknown';
          final displayName =
              (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : username;
          final trustTier = user['trust_tier'] as String? ?? 'unverified';
          byEcho[echoId] = EchoReplyPreview(
            id: row['id'] as String,
            content: row['content'] as String? ?? '',
            username: username,
            displayName: displayName,
            userId: replyUserId ?? user['id'] as String? ?? '',
            avatarUrl: user['avatar_url'] as String?,
            userTrustTier: trustTier,
            userIsVerified: trustTier == 'high' || trustTier == 'elite',
            userIsPro: user['is_pro'] as bool? ?? false,
            isLiked: likedReplyIds.contains(row['id'] as String),
            isFromFollowed: isFromFollowed,
            likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
            childReplyCount: (row['child_reply_count'] as num?)?.toInt() ?? 0,
            createdAt: _parseDate(row['created_at']),
          );
        }
      }

      return echoes
          .map(
            (echo) => echo.copyWith(
              previewReplies: byEcho[echo.id] == null
                  ? const []
                  : [byEcho[echo.id]!],
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.warn('feed: reply previews skipped $e');
      return echoes;
    }
  }

  EchoEntity _mapToEntity(Map<String, dynamic> row, Map<String, dynamic> user) {
    final created =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final trustTier = user['trust_tier'] as String? ?? 'unverified';

    return EchoEntity(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String,
      username: user['username'] as String,
      userDisplayName:
          (user['display_name'] as String?)?.trim().isNotEmpty == true
          ? user['display_name'] as String
          : user['username'] as String,
      userTrustTier: trustTier,
      userIsVerified:
          (user['is_identity_verified'] as bool? ?? false) ||
          trustTier == 'high' ||
          trustTier == 'elite',
      userIsPro: user['is_pro'] as bool? ?? false,
      // is_identity_verified is on users_private not users_public
      // so fallback queries will return null here and default to false
      // only the edge function which does a join to users_private will have this
      userAvatarUrl: user['avatar_url'] as String?,
      category: EchoCategory.fromString(row['category'] as String),
      categoryDetail: row['category_detail'] as String?,
      status: _parseStatus(row['status'] as String),
      confidenceScore: (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
      trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
      supportCount:
          (row['context_support_count'] as num?)?.toInt() ??
          (row['support_count'] as num?)?.toInt() ??
          0,
      challengeCount:
          (row['context_challenge_count'] as num?)?.toInt() ??
          (row['challenge_count'] as num?)?.toInt() ??
          0,
      contextSupportCount: (row['context_support_count'] as num?)?.toInt() ?? 0,
      contextChallengeCount:
          (row['context_challenge_count'] as num?)?.toInt() ?? 0,
      publicVerdict: row['public_verdict'] as String? ?? 'open',
      publicVerdictAt: _parseDate(row['public_verdict_at']),
      publicContextClosesAt: _parseDate(row['public_context_closes_at']),
      publicContextMinCount:
          (row['public_context_min_count'] as num?)?.toInt() ?? 7,
      publicContextDecisionReason:
          row['public_context_decision_reason'] as String?,
      contextScore: (row['context_score'] as num?)?.toInt() ?? 0,
      timeAgo: Formatters.timeAgo(created),
      mediaUrls: (row['media_urls'] as List?)?.cast<String>() ?? const [],
      replyCount: (row['reply_count'] as num?)?.toInt() ?? 0,
      proofCount: (row['proof_count'] as num?)?.toInt() ?? 0,
      userId: row['user_id'] as String? ?? '',
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
}
