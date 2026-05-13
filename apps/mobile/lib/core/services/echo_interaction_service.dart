// echo interaction service
// calls the on-interaction supabase edge function
// returns updated echo scores for optimistic ui sync

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/echo/domain/entities/echo_entity.dart';
import '../../features/echo/domain/entities/echo_status.dart';
import 'connectivity_service.dart';
import '../utils/logger.dart';

class EchoInteractionResult {
  const EchoInteractionResult({required this.updatedEcho});
  final EchoEntity updatedEcho;
}

class EchoInteractionService {
  EchoInteractionService(SupabaseClient _, this._supabaseUrl);

  final String _supabaseUrl;

  Future<EchoInteractionResult> interact({
    required String echoId,
    required String type,
    required String jwtToken,
  }) async {
    if (!ConnectivityService.instance.isOnline) {
      throw Exception('No internet connection. Try again when you are online.');
    }

    final supabaseUrl = Supabase.instance.client.auth.currentSession != null
        ? _supabaseUrl
        : _supabaseUrl;
    final url = '$supabaseUrl/functions/v1/on-interaction';
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    AppLogger.debug('interaction: posting $type on $echoId');

    final response = await http.post(
      Uri.parse(url),
      headers: {
        if (anonKey.isNotEmpty) 'apikey': anonKey,
        'Authorization': 'Bearer $jwtToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'echo_id': echoId,
        'type': type,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final echoMap = data['echo'] as Map<String, dynamic>? ?? {};

      AppLogger.info('interaction: success $type on $echoId');

      return EchoInteractionResult(
        updatedEcho: _echoFromMap(echoId, echoMap),
      );
    }

    if (response.statusCode == 429) {
      throw Exception('Too many interactions — slow down.');
    }
    if (response.statusCode == 403) {
      throw Exception('You are not allowed to do this.');
    }

    throw Exception('Interaction failed (${response.statusCode})');
  }

  EchoEntity _echoFromMap(String echoId, Map<String, dynamic> map) {
    return EchoEntity(
      id: echoId,
      title: '',
      userIsPro: false,
      content: '',
      username: '',
      userDisplayName: '',
      userTrustTier: 'unverified',
      userIsVerified: false,
      userAvatarUrl: null,
      category: EchoCategory.other,
      status: _parseStatus(map['status'] as String? ?? 'active'),
      confidenceScore: (map['confidence_score'] as num?)?.toDouble() ?? 0.0,
      trustScore: (map['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (map['controversy_score'] as num?)?.toDouble() ?? 0.0,
      supportCount: (map['support_count'] as num?)?.toInt() ?? 0,
      challengeCount: (map['challenge_count'] as num?)?.toInt() ?? 0,
      timeAgo: '',
    );
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
