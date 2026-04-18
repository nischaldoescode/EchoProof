// auth provider — manages supabase auth session state
// exposes: current user stream, sign in, sign out, google oauth
// all ui reacts to authStateProvider automatically via riverpod

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// raw supabase client — import this when you need direct db access
final supabaseProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// streams the current auth user — null when logged out
/// widgets use this to gate screens (splash → login or feed)
final authStateProvider = StreamProvider<User?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client.auth.onAuthStateChange.map((event) => event.session?.user);
});

/// current user id — throws if called when logged out
final currentUserIdProvider = Provider<String>((ref) {
  final client = ref.watch(supabaseProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw StateError('no authenticated user');
  return userId;
});

/// auth actions — sign in, sign out, google oauth
class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    return ref.watch(supabaseProvider).auth.currentUser;
  }

  /// sign in with email and password.
  /// throws AuthException on invalid credentials.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(supabaseProvider).auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.user;
    });
  }

  /// sign up with email and password.
  /// triggers onboarding flow after success.
  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final response = await ref.read(supabaseProvider).auth.signUp(
        email: email,
        password: password,
      );
      return response.user;
    });
  }

  /// google oauth — opens browser, returns to app via deep link
  ///
  /// TODO: configure deep link redirect uri in supabase dashboard
  /// go to: supabase project > authentication > url configuration
  /// add redirect url: echoproof://auth-callback
  /// also add to AndroidManifest.xml intent filter and ios Info.plist
  /// parameters: redirectTo should match your app scheme exactly
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(supabaseProvider).auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'echoproof://auth-callback',
      );
      return ref.read(supabaseProvider).auth.currentUser;
    });
  }

  /// signs out the current user and clears local session
  Future<void> signOut() async {
    await ref.read(supabaseProvider).auth.signOut();
    state = const AsyncData(null);
  }
}

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, User?>(
  AuthNotifier.new,
);