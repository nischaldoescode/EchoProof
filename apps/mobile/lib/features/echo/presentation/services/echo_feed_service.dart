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
            support_count, challenge_count, created_at,
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
      final results = await _fetchPage(offset: 0);
      _echoes = results;
      _hasMore = results.length == _kPageSize;
      _loadState = FeedLoadState.idle;
      AppLogger.info(
          'feed: loaded ${results.length} echoes from edge function');
    } catch (e) {
      AppLogger.warn('feed: edge function failed ($e), trying fallback');
      try {
        final fallback = await _fetchFallback();
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
      final more = await _fetchPage(offset: _offset);
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
      final results = await _fetchPage(offset: 0, forceRefresh: true);
      _echoes = results;
      _hasMore = results.length == _kPageSize;
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
    final refreshParam = forceRefresh ? '&refresh=1' : '';

    final response = await http.get(
      Uri.parse(
        '$supabaseUrl/functions/v1/personalized-feed'
        '?offset=$offset&limit=$_kPageSize$refreshParam',
      ),
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
    final created =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();

    return EchoEntity(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String,
      username: user['username'] as String,
      userDisplayName:
          (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : user['username'] as String,
      userTrustTier: user['trust_tier'] as String? ?? 'unverified',
      userIsVerified: user['is_identity_verified'] as bool? ?? false,
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
      supportCount: (row['support_count'] as num?)?.toInt() ?? 0,
      challengeCount: (row['challenge_count'] as num?)?.toInt() ?? 0,
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
