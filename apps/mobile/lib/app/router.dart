// app router — declarative navigation using go_router
// redirects to login if unauthenticated, onboarding if not yet complete

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/providers/auth_provider.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/onboarding/presentation/providers/onboarding_provider.dart';
import '../features/onboarding/presentation/screens/onboarding_root.dart';
import '../features/echo/presentation/screens/feed_screen.dart';
import '../features/echo/presentation/screens/create_echo_screen.dart';
import '../features/echo/presentation/screens/echo_detail_screen.dart';
import '../features/echo/presentation/screens/discover_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, routerState) {
      final isLoggedIn = authState.valueOrNull != null;
      final isOnboardingDone = ref.read(isOnboardingCompleteProvider);
      final location = routerState.matchedLocation;

      // still loading — stay on splash
      if (authState.isLoading) return location == '/splash' ? null : '/splash';

      // not logged in — send to login
      if (!isLoggedIn && location != '/login') return '/login';

      // logged in but onboarding not done — send to onboarding
      if (isLoggedIn && !isOnboardingDone && location != '/onboarding') {
        return '/onboarding';
      }

      // logged in + onboarding done — if still on login or splash, go to feed
      if (isLoggedIn && isOnboardingDone &&
          (location == '/login' || location == '/splash')) {
        return '/feed';
      }

      return null; // no redirect needed
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingRoot(),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, state) => const FeedScreen(),
        routes: [
          GoRoute(
            path: 'echo/:id',
            builder: (context, state) => EchoDetailScreen(
              echoId: state.pathParameters['id']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreateEchoScreen(),
      ),
      GoRoute(
  path: '/discover',
  builder: (context, state) => const DiscoverScreen(),
),
      
    ],
  );
});