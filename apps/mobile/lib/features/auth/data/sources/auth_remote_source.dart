// auth remote data source
// direct supabase auth calls no business logic here

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../../../../core/utils/logger.dart';

class AuthRemoteSource {
  const AuthRemoteSource(this._client);
  final SupabaseClient _client;

  Future<UserModel> signInWithEmail({
    required String email,
    required String password,
  }) async {
    AppLogger.info('auth: sign in with email');

    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('sign in failed');
    }

    return _fetchPublicProfile(response.user!.id);
  }

  Future<UserModel> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    AppLogger.info('auth: sign up with email');

    final response = await _client.auth.signUp(
      email: email,
      password: password,
    );

    if (response.user == null) {
      throw const AuthException('sign up failed');
    }

    // new users do not have a users_public row yet
    // the onboarding flow creates it after they pick a username
    return UserModel(
      id: response.user!.id,
      username: '',
      trustTier: 'unverified',
      trustScore: 0,
      isIdentityVerified: false,
    );
  }

  Future<UserModel> signInWithGoogle() async {
    AppLogger.info('auth: sign in with google');

    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'echoproof://auth-callback',
    );

    // oauth redirects to the app the session is set by the deep link handler
    // after redirect, currentuser is available
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('google sign in failed');

    return _fetchPublicProfile(user.id);
  }

  Future<void> signOut() async {
    AppLogger.info('auth: sign out');
    await _client.auth.signOut();
  }

  Future<UserModel?> getCurrentUser() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    return _fetchPublicProfile(user.id);
  }

  // fetches the public profile row for a given user id
  // returns a minimal model if the row does not exist yet (new user)
  Future<UserModel> _fetchPublicProfile(String userId) async {
    try {
      final row = await _client
          .from('users_public')
          .select(
              'id, username, trust_tier, trust_score, avatar_url, wallet_address')
          .eq('id', userId)
          .maybeSingle();

      if (row == null) {
        // user exists in auth but has not completed onboarding
        return UserModel(
          id: userId,
          username: '',
          trustTier: 'unverified',
          trustScore: 0,
          isIdentityVerified: false,
        );
      }

      // check identity verification from private table
      final privateRow = await _client
          .from('users_private')
          .select('is_identity_verified')
          .eq('id', userId)
          .maybeSingle();

      return UserModel(
        id: row['id'] as String,
        username: row['username'] as String? ?? '',
        trustTier: row['trust_tier'] as String? ?? 'unverified',
        trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
        isIdentityVerified:
            privateRow?['is_identity_verified'] as bool? ?? false,
        avatarUrl: row['avatar_url'] as String?,
        walletAddress: row['wallet_address'] as String?,
      );
    } catch (e) {
      AppLogger.error('auth: fetch public profile failed', e);
      rethrow;
    }
  }
}
