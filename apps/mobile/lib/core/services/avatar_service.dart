// avatar service
// generates a deterministic dicebear avatar from the username,
// downloads it once, stores in supabase storage, saves url to users_public
// after first generation, the storage url is used forever — no repeat api calls

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class AvatarService {
  AvatarService(this._client);

  final SupabaseClient _client;

  // dicebear styles that match the echoproof aesthetic:
  // 'identicon' = geometric shapes (clean, minimal)
  // 'bottts-neutral' = robot style (fun but neutral)
  // 'shapes' = abstract shapes (most minimal, best for trust app)
  static const _style = 'shapes';
  static const _size  = 128; // 128x128 pixels is enough, keeps file small

  /// generates avatar for a user if they don't have one yet.
  /// called once at end of onboarding after username is saved.
  /// [userId] — the auth user id, used as storage path
  /// [username] — used as the dicebear seed (same username = same avatar always)
  Future<String> generateAndStore({
    required String userId,
    required String username,
  }) async {
    // check if user already has an avatar — don't regenerate
    final existing = await _client
        .from('users_public')
        .select('avatar_url')
        .eq('id', userId)
        .single();

    final existingUrl = existing['avatar_url'] as String?;
    if (existingUrl != null && existingUrl.isNotEmpty) {
      return existingUrl;
    }

    // build dicebear url
    // format: https://api.dicebear.com/9.x/{style}/png?seed={seed}&size={size}
    // using png not svg because supabase img transforms work on png
    final dicebearUrl =
        'https://api.dicebear.com/9.x/$_style/png?seed=$username&size=$_size';

    // download the png bytes
    final response = await http.get(Uri.parse(dicebearUrl));
    if (response.statusCode != 200) {
      throw Exception('failed to fetch avatar from dicebear: ${response.statusCode}');
    }

    final bytes = response.bodyBytes;

    // upload to supabase storage
    // bucket: 'avatars' — make sure this exists in supabase dashboard
    // path: avatars/{userId}.png — one file per user, overwrite-safe
    final storagePath = '$userId.png';

    await _client.storage
        .from('avatars')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/png',
            upsert: true, // overwrite if somehow called again
          ),
        );

    // get the public url from supabase storage
    final publicUrl = _client.storage
        .from('avatars')
        .getPublicUrl(storagePath);

    // save url to users_public row
    await _client
        .from('users_public')
        .update({'avatar_url': publicUrl})
        .eq('id', userId);

    return publicUrl;
  }
}

final avatarServiceProvider = Provider<AvatarService>((ref) {
  return AvatarService(Supabase.instance.client);
});