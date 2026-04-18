// echo remote data source
// direct supabase queries — no business logic here

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/echo_entity.dart';
import '../models/echo_model.dart';
import '../../../../core/utils/logger.dart';

class EchoRemoteSource {
  const EchoRemoteSource(this._client);
  final SupabaseClient _client;

  Future<List<EchoEntity>> fetchFeed({required int offset, required int limit}) async {
    AppLogger.debug('remote: fetch feed offset=$offset limit=$limit');

    final response = await _client
        .from('echoes')
        .select('''
          id, title, content, category, status,
          trust_score, confidence_score, controversy_score,
          support_count, challenge_count, created_at,
          users_public!inner(username, avatar_url, trust_tier, is_identity_verified)
        ''')
        .not('status', 'in', '("hidden","rejected")')
        .order('trust_score', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List).map((row) {
      final user = row['users_public'] as Map<String, dynamic>;
      return EchoModel.fromRow(row as Map<String, dynamic>, user);
    }).toList();
  }

  Future<EchoEntity> fetchById(String id) async {
    final row = await _client
        .from('echoes')
        .select('''
          id, title, content, category, status,
          trust_score, confidence_score, controversy_score,
          support_count, challenge_count, created_at,
          users_public!inner(username, avatar_url, trust_tier, is_identity_verified)
        ''')
        .eq('id', id)
        .single();

    final user = row['users_public'] as Map<String, dynamic>;
    return EchoModel.fromRow(row, user);
  }

  Future<EchoEntity> createEcho({
    required String title,
    required String content,
    required EchoCategory category,
    required bool verificationRequired,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('not authenticated');

    final inserted = await _client.from('echoes').insert({
      'user_id':              userId,
      'title':                title.trim(),
      'content':              content.trim(),
      'category':             category.name,
      'verification_required': verificationRequired,
      'status':               'pending_verification',
    }).select('''
      id, title, content, category, status,
      trust_score, confidence_score, controversy_score,
      support_count, challenge_count, created_at,
      users_public!inner(username, avatar_url, trust_tier, is_identity_verified)
    ''').single();

    final user = inserted['users_public'] as Map<String, dynamic>;
    return EchoModel.fromRow(inserted, user);
  }

  Future<void> interact({required String echoId, required String type}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('not authenticated');

    await _client.from('echo_interactions').upsert({
      'echo_id': echoId,
      'user_id': userId,
      'type':    type,
    }, onConflict: 'echo_id,user_id');
  }

  Future<void> report({
    required String echoId,
    required String reason,
    String? description,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('not authenticated');

    await _client.from('echo_reports').insert({
      'echo_id':     echoId,
      'reporter_id': userId,
      'reason':      reason,
      'description': description,
    });
  }
}