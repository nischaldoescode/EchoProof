// signal drift score service
// @params none

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/logger.dart';

class SignalDriftScoreResult {
  const SignalDriftScoreResult({
    required this.accepted,
    required this.reason,
    required this.highScore,
    required this.localOnly,
  });

  final bool accepted;
  final String reason;
  final int highScore;
  final bool localOnly;
}

class SignalDriftScoreService {
  SignalDriftScoreService({
    SupabaseClient? client,
    Box<dynamic>? box,
  })  : _client = client ?? Supabase.instance.client,
        _box = box ?? Hive.box('app_settings');

  static const _kLocalHighScore = 'signal_drift_local_high_score';
  static const _kServerHighScore = 'signal_drift_server_high_score';
  static const _kLastSyncMs = 'signal_drift_last_sync_ms';

  final SupabaseClient _client;
  final Box<dynamic> _box;
  final Random _secureRandom = Random.secure();

  int get localHighScore {
    final local = _box.get(_kLocalHighScore, defaultValue: 0) as int;
    final server = _box.get(_kServerHighScore, defaultValue: 0) as int;
    return max(local, server);
  }

  Future<int> loadBestScore() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return localHighScore;

    try {
      final row = await _client
          .from('signal_drift_scores')
          .select('high_score')
          .eq('user_id', userId)
          .maybeSingle();
      final serverScore = (row?['high_score'] as num?)?.toInt() ?? 0;
      if (serverScore > 0) {
        await _box.put(_kServerHighScore, serverScore);
        await _box.put(_kLocalHighScore, max(localHighScore, serverScore));
      }
      await _box.put(_kLastSyncMs, DateTime.now().millisecondsSinceEpoch);
    } catch (error, stack) {
      AppLogger.warn('signal drift: high score sync failed $error');
      AppLogger.debug('signal drift: high score sync stack $stack');
    }

    return localHighScore;
  }

  Future<SignalDriftScoreResult> submitScore({
    required int score,
    required int runMs,
  }) async {
    final currentLocal = localHighScore;
    if (score > currentLocal) {
      await _box.put(_kLocalHighScore, score);
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null || score <= 0) {
      return SignalDriftScoreResult(
        accepted: false,
        reason: userId == null ? 'signed_out' : 'zero_score',
        highScore: localHighScore,
        localOnly: true,
      );
    }

    final nonce = _nonce();
    // checksum mirrors the sql rpc to catch tampered payloads
    final checksum =
        sha256.convert(utf8.encode('$nonce:$score:$runMs:$userId')).toString();

    try {
      final response = await _client.rpc(
        'submit_signal_drift_score',
        params: {
          'p_score': score,
          'p_run_ms': runMs,
          'p_client_nonce': nonce,
          'p_checksum': checksum,
        },
      );
      final data = Map<String, dynamic>.from(response as Map);
      final highScore = (data['high_score'] as num?)?.toInt() ?? localHighScore;
      await _box.put(_kServerHighScore, highScore);
      await _box.put(_kLocalHighScore, max(localHighScore, highScore));
      await _box.put(_kLastSyncMs, DateTime.now().millisecondsSinceEpoch);
      return SignalDriftScoreResult(
        accepted: data['accepted'] == true,
        reason: data['reason'] as String? ?? 'unknown',
        highScore: highScore,
        localOnly: false,
      );
    } catch (error, stack) {
      AppLogger.warn('signal drift: score submit failed $error');
      AppLogger.debug('signal drift: score submit stack $stack');
      return SignalDriftScoreResult(
        accepted: false,
        reason: 'offline',
        highScore: localHighScore,
        localOnly: true,
      );
    }
  }

  String _nonce() {
    final bytes = Uint8List(24);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
