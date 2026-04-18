import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/echo/domain/entities/echo_entity.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';

// -------------------------------------------------------------
// Result model
// -------------------------------------------------------------
class EchoInteractionResult {
  final EchoEntity updatedEcho;

  EchoInteractionResult({required this.updatedEcho});
}

// -------------------------------------------------------------
// Service
// -------------------------------------------------------------
class EchoInteractionService {
  EchoInteractionService(this._client, this._supabaseUrl);

  final SupabaseClient _client;
  final String _supabaseUrl;

  Future<EchoInteractionResult> interact({
    required String echoId,
    required String type,
    required String jwtToken,
  }) async {
    final supabaseUrl = Supabase.instance.client.auth.currentSession != null
        ? _supabaseUrl
        : _supabaseUrl;
    final url = '$supabaseUrl/functions/v1/on-interaction';

    final response = await http.post(
      Uri.parse(url),
      headers: {
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
      return EchoInteractionResult(
        updatedEcho: EchoEntity.fromJson(data['echo'] as Map<String, dynamic>),
      );
    }

    if (response.statusCode == 429)
      throw Exception('Too many interactions — slow down.');
    if (response.statusCode == 403)
      throw Exception('You are not allowed to do this.');
    throw Exception('Interaction failed (${response.statusCode})');
  }
}

// -------------------------------------------------------------
// Provider
// -------------------------------------------------------------
final echoInteractionServiceProvider = Provider<EchoInteractionService>((ref) {
  final client = ref.read(supabaseProvider);
  const url = String.fromEnvironment('SUPABASE_URL');

  return EchoInteractionService(client, url);
});
