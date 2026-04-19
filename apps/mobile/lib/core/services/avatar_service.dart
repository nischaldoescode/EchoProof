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
  static const _size  = 128;

  // generates and stores avatar for a user.
  // safe to call multiple times — checks if avatar already exists first.
  Future<String> generateAndStore({
    required String userId,
    required String username,
  }) async {
    // check if user already has an avatar
    final existing = await _client
        .from('users_public')
        .select('avatar_url')
        .eq('id', userId)
        .single();

    final existingUrl = existing['avatar_url'] as String?;
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

    await _client.storage
        .from('avatars')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true,
          ),
        );

    // get public cdn url
    final publicUrl = _client.storage
        .from('avatars')
        .getPublicUrl(storagePath);

    // save url to users_public
    await _client
        .from('users_public')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);

    AppLogger.info('avatar: generated and stored for $username');
    return publicUrl;
  }
}