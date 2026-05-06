// avatar service
// generates a deterministic dicebear avatar, downloads it once,
// uploads to supabase storage, saves url to users_public.avatar_url
// called once at end of onboarding — never again

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

class AvatarService {
  AvatarService(this._client);

  final SupabaseClient _client;

  static const _style = 'shapes';
  static const _size = 128;

  // generates and stores avatar for a user.
  // safe to call multiple times — checks if avatar already exists first.
  Future<String> generateAndStore({
    required String userId,
    required String username,
  }) async {
    // Use maybeSingle so that a missing row returns null instead of throwing
    // PGRST116. New users may not have a row yet if the DB trigger is slow.
    final existing = await _client
        .from('users_public')
        .select('avatar_url')
        .eq('id', userId)
        .maybeSingle();

    final existingUrl = existing?['avatar_url'] as String?;
    if (existingUrl != null && existingUrl.isNotEmpty) {
      AppLogger.debug('avatar: already exists, skipping generation');
      return existingUrl;
    }

    // fetch from dicebear — png format, shapes style
    final dicebearUrl =
        'https://api.dicebear.com/9.x/$_style/png?seed=$username&size=$_size';

    final response = await http.get(Uri.parse(dicebearUrl));
    if (response.statusCode != 200) {
      throw Exception(
        'dicebear fetch failed: ${response.statusCode}',
      );
    }

    final bytes = response.bodyBytes;

    // upload to supabase storage bucket 'avatars'
    final storagePath = '$userId.png';

// upload to storage
    await _client.storage.from('avatars').uploadBinary(
          '$userId.png',
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );

    // get public URL
    final url = _client.storage.from('avatars').getPublicUrl('$userId.png');

    // Try UPDATE first, then INSERT if no row exists yet.
    // This mirrors the same pattern as completeOnboarding to handle
    // new users where the DB trigger row may not exist.
    final updated = await _client
        .from('users_public')
        .update({'avatar_url': url})
        .eq('id', userId)
        .select('id');

    if ((updated as List).isEmpty) {
      // Row doesn't exist yet — insert a minimal row with avatar_url.
      // completeOnboarding will fill in the rest shortly after.
      final tempUsername = 'user${userId.replaceAll('-', '').substring(0, 8)}';
      await _client.from('users_public').insert({
        'id': userId,
        'username': tempUsername,
        'avatar_url': url,
        'trust_tier': 'unverified',
        'trust_score': 0,
        'echo_count': 0,
        'proof_count': 0,
        'is_public': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    AppLogger.info(
        'avatar: generated and stored for ${userId.substring(0, 8)}');
    return url;
  }
}
