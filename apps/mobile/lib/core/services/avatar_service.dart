// avatar service
// generates a deterministic dicebear avatar, downloads it once,
// uploads to supabase storage, saves url to users_public.avatar_url
// called once at end of onboarding never again

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../utils/logger.dart';

class AvatarService {
  AvatarService(this._client);

  final SupabaseClient _client;

  static const _style = 'lorelei';
  static const _size = 128;

  static String defaultAvatarUrlFor(String userId) {
    final seedSource = userId.replaceAll('-', '');
    final seed = seedSource.length >= 8 ? seedSource.substring(0, 8) : userId;
    return Uri.https(
      'api.dicebear.com',
      '/9.x/$_style/png',
      {'seed': seed, 'size': '$_size'},
    ).toString();
  }

  // generates and stores avatar for a user
  // safe to call multiple times checks if avatar already exists first
  Future<String> generateAndStore({
    required String userId,
    required String username,
  }) async {
    // use maybesingle so that a missing row returns null instead of throwing
    // pgrst116. new users may not have a row yet if the db trigger is slow
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

    final fallbackUrl = defaultAvatarUrlFor(userId);
    await _writeAvatarUrl(
      userId: userId,
      username: username,
      url: fallbackUrl,
    );

    http.Response response;
    try {
      response = await http.get(Uri.parse(fallbackUrl));
      if (response.statusCode != 200) {
        throw Exception('dicebear fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.warn('avatar: using deterministic remote avatar: $e');
      return fallbackUrl;
    }

    final bytes = response.bodyBytes;

    // store a local copy when storage is available; the remote url is already
    // saved as a fallback so onboarding never ends with a blank avatar
    final storagePath = '$userId.png';
    try {
      await _client.storage.from('avatars').uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: true,
            ),
          );

      final url = _client.storage.from('avatars').getPublicUrl(storagePath);

      await _writeAvatarUrl(userId: userId, username: username, url: url);

      AppLogger.info(
          'avatar: generated and stored for ${userId.substring(0, 8)}');
      return url;
    } catch (e) {
      AppLogger.warn(
          'avatar: storage upload failed, keeping remote avatar: $e');
      return fallbackUrl;
    }
  }

  Future<void> _writeAvatarUrl({
    required String userId,
    required String username,
    required String url,
  }) async {
    final updated = await _client
        .from('users_public')
        .update({'avatar_url': url})
        .eq('id', userId)
        .select('id');

    if ((updated as List).isEmpty) {
      // row doesn't exist yet insert a minimal row with avatar_url
      // completeonboarding will fill in the rest shortly after
      final tempUsername = 'user${userId.replaceAll('-', '').substring(0, 8)}';
      await _client.from('users_public').insert({
        'id': userId,
        'username': username.isNotEmpty ? username : tempUsername,
        'display_name': username.isNotEmpty ? username : tempUsername,
        'avatar_url': url,
        'trust_tier': 'unverified',
        'trust_score': 0,
        'echo_count': 0,
        'proof_count': 0,
        'is_public': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }
}
