// bookmark service
// @params none
// keeps saved echoes synced between memory hive and supabase

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/logger.dart';
import '../../data/models/echo_model.dart';
import '../../domain/entities/echo_entity.dart';

class BookmarkService extends ChangeNotifier {
  final Set<String> _ids = {};
  bool _loaded = false;
  bool _loading = false;
  bool _serverAvailable = true;

  bool get isLoaded => _loaded;
  bool isBookmarked(String echoId) => _ids.contains(echoId);

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await loadBookmarks();
  }

  Future<void> loadBookmarks() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _ids.clear();
      _loaded = true;
      notifyListeners();
      return;
    }

    _loading = true;
    final local = _readLocal(userId);
    if (local.isNotEmpty) {
      _ids
        ..clear()
        ..addAll(local);
      notifyListeners();
    }

    try {
      final rows = await Supabase.instance.client
          .from('echo_bookmarks')
          .select('echo_id')
          .eq('user_id', userId);
      final remoteIds = List<Map<String, dynamic>>.from(
        rows as List,
      ).map((row) => row['echo_id'] as String?).whereType<String>().toSet();
      _serverAvailable = true;
      _ids
        ..clear()
        ..addAll(remoteIds);
      await _writeLocal(userId);
    } on PostgrestException catch (e) {
      _serverAvailable = e.code != '42P01' && e.code != 'PGRST205';
      AppLogger.warn('bookmarks: remote load skipped ${e.code}');
    } catch (e) {
      AppLogger.warn('bookmarks: remote load failed $e');
    } finally {
      _loaded = true;
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> toggle(String echoId) async {
    await ensureLoaded();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return false;

    final nextSaved = !_ids.contains(echoId);
    if (nextSaved) {
      _ids.add(echoId);
    } else {
      _ids.remove(echoId);
    }
    await _writeLocal(userId);
    notifyListeners();

    if (!_serverAvailable) return true;
    try {
      if (nextSaved) {
        await Supabase.instance.client.from('echo_bookmarks').upsert({
          'user_id': userId,
          'echo_id': echoId,
        }, onConflict: 'user_id,echo_id');
      } else {
        await Supabase.instance.client
            .from('echo_bookmarks')
            .delete()
            .eq('user_id', userId)
            .eq('echo_id', echoId);
      }
      return true;
    } on PostgrestException catch (e) {
      _serverAvailable = e.code != '42P01' && e.code != 'PGRST205';
      AppLogger.warn('bookmarks: remote toggle skipped ${e.code}');
      return true;
    } catch (e) {
      if (nextSaved) {
        _ids.remove(echoId);
      } else {
        _ids.add(echoId);
      }
      await _writeLocal(userId);
      notifyListeners();
      AppLogger.warn('bookmarks: toggle failed $e');
      return false;
    }
  }

  Future<List<EchoEntity>> fetchBookmarkedEchoes() async {
    await ensureLoaded();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return const [];

    try {
      final rows = await Supabase.instance.client
          .from('echo_bookmarks')
          .select('''
            created_at,
            echoes!inner(
              id, user_id, title, content, category, category_detail, status,
              version, media_urls, reply_count, proof_count, bond_count,
              trust_score, confidence_score, controversy_score,
              support_count, challenge_count, context_support_count,
              context_challenge_count, context_score, public_verdict,
              public_verdict_at, public_context_closes_at,
              public_context_min_count, public_context_decision_reason,
              created_at, created_record_tx, created_record_at,
              solana_status, solana_error, verified_record_tx,
              verified_record_at, verified_record_status,
              verified_record_error,
              users_public!echoes_user_id_fkey!inner(
                username, display_name, avatar_url, trust_tier, is_pro
              )
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      _serverAvailable = true;
      return _mapBookmarkRows(rows as List);
    } on PostgrestException catch (e) {
      _serverAvailable = e.code != '42P01' && e.code != 'PGRST205';
      AppLogger.warn('bookmarks: remote fetch skipped ${e.code}');
      return _fetchLocalFallback();
    } catch (e) {
      AppLogger.warn('bookmarks: remote fetch failed $e');
      return _fetchLocalFallback();
    }
  }

  Future<List<EchoEntity>> _fetchLocalFallback() async {
    if (_ids.isEmpty) return const [];
    final ids = _ids.take(60).join(',');
    final rows = await Supabase.instance.client
        .from('echoes')
        .select('''
          id, user_id, title, content, category, category_detail, status,
          version, media_urls, reply_count, proof_count, bond_count,
          trust_score, confidence_score, controversy_score,
          support_count, challenge_count, context_support_count,
          context_challenge_count, context_score, public_verdict,
          public_verdict_at, public_context_closes_at,
          public_context_min_count, public_context_decision_reason, created_at,
          created_record_tx, created_record_at, solana_status, solana_error,
          verified_record_tx, verified_record_at,
          verified_record_status, verified_record_error,
          users_public!echoes_user_id_fkey!inner(username, display_name, avatar_url, trust_tier, is_pro)
        ''')
        .filter('id', 'in', '($ids)')
        .not('status', 'in', '("hidden","rejected")');
    return List<Map<String, dynamic>>.from(rows as List).map((row) {
      final user = row['users_public'] as Map<String, dynamic>;
      return EchoModel.fromRow(row, user);
    }).toList();
  }

  List<EchoEntity> _mapBookmarkRows(List rows) {
    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) => row['echoes'])
        .whereType<Map<String, dynamic>>()
        .map((echoRow) {
          final user = echoRow['users_public'] as Map<String, dynamic>;
          return EchoModel.fromRow(echoRow, user);
        })
        .toList();
  }

  void clearForLogout() {
    _ids.clear();
    _loaded = false;
    _loading = false;
    notifyListeners();
  }

  Set<String> _readLocal(String userId) {
    final raw = Hive.box('app_settings').get('bookmarks_$userId');
    if (raw is List) return raw.whereType<String>().toSet();
    return {};
  }

  Future<void> _writeLocal(String userId) {
    return Hive.box('app_settings').put('bookmarks_$userId', _ids.toList());
  }
}
