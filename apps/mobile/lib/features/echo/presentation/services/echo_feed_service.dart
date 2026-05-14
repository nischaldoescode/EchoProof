// echo feed service
// fetches and manages the personalized feed
// replaces: echo_feed_provider.dart (riverpod version)
// screens listen via context.watch<EchoFeedService>()

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/formatters.dart';

const _kPageSize = 20;

enum FeedLoadState { idle, loading, loadingMore, error }

class EchoFeedService extends ChangeNotifier {
  List<EchoEntity> _echoes = [];
  List<EchoEntity> get echoes => List.unmodifiable(_echoes);

  FeedLoadState _loadState = FeedLoadState.idle;
  FeedLoadState get loadState => _loadState;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  String? _error;
  String? get error => _error;

  int _offset = 0;

  bool get isLoading => _loadState == FeedLoadState.loading;
  bool get isLoadingMore => _loadState == FeedLoadState.loadingMore;

  void removeEcho(String echoId) {
    final next = _echoes.where((echo) => echo.id != echoId).toList();
    if (next.length == _echoes.length) return;
    _echoes = next;
    notifyListeners();
  }

  Future<List<EchoEntity>> _fetchFallback() async {
    AppLogger.info('feed: running fallback direct DB query');
    final client = Supabase.instance.client;

    try {
      final userId = client.auth.currentUser?.id;
      final hiddenEchoIds = <String>{};
      final hiddenAuthorIds = <String>{};

      if (userId != null) {
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
          client
              .from('user_blocks')
              .select('blocked_id')
              .eq('blocker_id', userId),
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
      }

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
            users_public!inner(username, display_name, avatar_url, trust_tier, is_pro, is_public)
          ''')
          .not('status', 'in', '("hidden","rejected")')
          .eq('users_public.is_public', true)
          .order('created_at', ascending: false)
          .limit(_kPageSize);

      AppLogger.info('feed: fallback returned ${(rows as List).length} echoes');

      return (rows as List).where((row) {
        final r = row as Map<String, dynamic>;
        final echoId = r['id'] as String? ?? '';
        final authorId = r['user_id'] as String? ?? '';
        return !hiddenEchoIds.contains(echoId) &&
            !hiddenAuthorIds.contains(authorId);
      }).map((row) {
        final r = row as Map<String, dynamic>;
        final user = r['users_public'] as Map<String, dynamic>;
        return _mapToEntity(r, user);
      }).toList();
    } catch (e) {
      AppLogger.error('feed: fallback query failed: $e');
      rethrow;
    }
  }

  // loads the first page — call this when the feed screen mounts
  Future<void> loadFeed() async {
    if (_loadState == FeedLoadState.loading) return;
    _offset = 0;
    _loadState = FeedLoadState.loading;
    _error = null;
    notifyListeners();

    AppLogger.info('feed: loadFeed called');

    try {
      final page = await _fetchPage(offset: 0);
      final results = await _decorateFeed(page, includeFollowedLikes: true);
      _echoes = results;
      _hasMore = page.length == _kPageSize;
      _loadState = FeedLoadState.idle;
      AppLogger.info(
          'feed: loaded ${results.length} echoes from edge function');
    } catch (e) {
      AppLogger.warn('feed: edge function failed ($e), trying fallback');
      try {
        final fallback = await _decorateFeed(await _fetchFallback(),
            includeFollowedLikes: true);
        _echoes = fallback;
        _hasMore = false;
        _loadState = FeedLoadState.idle;
        AppLogger.info('feed: fallback loaded ${fallback.length} echoes');
      } catch (e2) {
        AppLogger.error(
            'feed: both edge function and fallback failed. edge=$e fallback=$e2');
        _loadState = FeedLoadState.error;
        _error = 'could not load feed';
      }
    }
    notifyListeners();
  }

  // loads next page and appends — call when user scrolls near bottom
  Future<void> loadMore() async {
    if (_loadState == FeedLoadState.loadingMore || !_hasMore) return;
    _loadState = FeedLoadState.loadingMore;
    notifyListeners();

    try {
      _offset += _kPageSize;
      final more = await _decorateFeed(await _fetchPage(offset: _offset));
      _echoes = [..._echoes, ...more];
      _hasMore = more.length == _kPageSize;
    } catch (e) {
      AppLogger.error('feed: load more failed', e);
      _offset -= _kPageSize; // revert offset on failure
    }

    _loadState = FeedLoadState.idle;
    notifyListeners();
  }

  // pull to refresh — reloads from page 1 with cache bust
  Future<void> refresh() async {
    _offset = 0;
    _loadState = FeedLoadState.loading;
    _error = null;
    notifyListeners();

    try {
      final page = await _fetchPage(offset: 0, forceRefresh: true);
      final results = await _decorateFeed(page, includeFollowedLikes: true);
      _echoes = results;
      _hasMore = page.length == _kPageSize;
      _loadState = FeedLoadState.idle;
    } catch (e) {
      _loadState = FeedLoadState.error;
      _error = 'could not refresh feed';
    }
    notifyListeners();
  }

  // optimistic update — updates local state immediately before server confirms
  void applyOptimisticInteraction({
    required String echoId,
    required String type,
  }) {
    _echoes = _echoes.map((echo) {
      if (echo.id != echoId) return echo;
      return echo.copyWith(
        supportCount:
            type == 'support' ? echo.supportCount + 1 : echo.supportCount,
        challengeCount:
            type == 'challenge' ? echo.challengeCount + 1 : echo.challengeCount,
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
        supportCount:
            type == 'support' ? echo.supportCount - 1 : echo.supportCount,
        challengeCount:
            type == 'challenge' ? echo.challengeCount - 1 : echo.challengeCount,
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

  Future<List<EchoEntity>> _fetchPage({
    required int offset,
    bool forceRefresh = false,
  }) async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return [];

    final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    final anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
    final refreshParam = forceRefresh ? '&refresh=1' : '';

    final response = await http.get(
      Uri.parse(
        '$supabaseUrl/functions/v1/personalized-feed'
        '?offset=$offset&limit=$_kPageSize$refreshParam',
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

    return list.map((row) {
      final map = row as Map<String, dynamic>;
      final user = map['users_public'] as Map<String, dynamic>;
      return _mapToEntity(map, user);
    }).toList();
  }

  Future<List<EchoEntity>> _decorateFeed(
    List<EchoEntity> echoes, {
    bool includeFollowedLikes = false,
  }) async {
    if (echoes.isEmpty) return echoes;

    var decorated = echoes;
    if (includeFollowedLikes) {
      decorated = await _injectFollowedLikedEchoes(decorated);
    }
    decorated = await _attachSocialContext(decorated);
    decorated = await _attachContextPreviews(decorated);
    decorated = await _attachReplyPreviews(decorated);
    return decorated;
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
      for (final row
          in List<Map<String, dynamic>>.from(hiddenResults[0] as List)) {
        final echoId = row['echo_id'] as String?;
        if (echoId != null) hiddenEchoIds.add(echoId);
        if (row['feedback_type'] == 'block_author') {
          final authorId = row['author_id'] as String?;
          if (authorId != null) hiddenAuthorIds.add(authorId);
        }
      }
      for (final row
          in List<Map<String, dynamic>>.from(hiddenResults[1] as List)) {
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
            users_public!inner(username, display_name, avatar_url, trust_tier, is_pro, is_public)
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
            users_public!inner(
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
      final likedReplyIds = <String>{};
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
            List<Map<String, dynamic>>.from(likedRows as List)
                .map((row) => row['reply_id'] as String?)
                .whereType<String>(),
          );
        }
      }

      final byEcho = <String, EchoReplyPreview>{};
      for (final row in rowList) {
        if (row['parent_reply_id'] != null) continue;
        final echoId = row['echo_id'] as String?;
        if (echoId == null || byEcho.containsKey(echoId)) continue;
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
          userId: row['user_id'] as String? ?? user['id'] as String? ?? '',
          avatarUrl: user['avatar_url'] as String?,
          userTrustTier: trustTier,
          userIsVerified: trustTier == 'high' || trustTier == 'elite',
          userIsPro: user['is_pro'] as bool? ?? false,
          isLiked: likedReplyIds.contains(row['id'] as String),
          likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
          childReplyCount: (row['child_reply_count'] as num?)?.toInt() ?? 0,
          createdAt: _parseDate(row['created_at']),
        );
      }

      return echoes
          .map((echo) => echo.copyWith(
                previewReplies:
                    byEcho[echo.id] == null ? const [] : [byEcho[echo.id]!],
              ))
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
      userIsVerified: (user['is_identity_verified'] as bool? ?? false) ||
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
      supportCount: (row['context_support_count'] as num?)?.toInt() ??
          (row['support_count'] as num?)?.toInt() ??
          0,
      challengeCount: (row['context_challenge_count'] as num?)?.toInt() ??
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
