// app router
// declarative navigation with go_router
// no riverpod — uses plain service classes

import 'package:go_router/go_router.dart';
import '../features/auth/presentation/screens/splash_screen.dart';
import '../features/auth/presentation/screens/login_screen.dart';
import '../features/auth/presentation/screens/identity_verification_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_root.dart';
import '../features/echo/presentation/screens/feed_screen.dart';
import '../features/echo/presentation/screens/create_echo_screen.dart';
import '../features/echo/presentation/screens/echo_detail_screen.dart';
import '../features/echo/presentation/screens/discover_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/auth/presentation/services/auth_service.dart';
import '../features/onboarding/presentation/services/onboarding_service.dart';

GoRouter createRouter({
  required AuthService authService,
  required OnboardingService onboardingService,
}) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, routerState) {
      final isLoggedIn = authService.currentUser != null;
      final isOnboardingDone = onboardingService.isComplete();
      final location = routerState.matchedLocation;

      if (location == '/splash') return null;

      if (!isLoggedIn && location != '/login') return '/login';

      if (isLoggedIn && !isOnboardingDone && location != '/onboarding') {
        return '/onboarding';
      }

      if (isLoggedIn &&
          isOnboardingDone &&
          (location == '/login' || location == '/splash')) {
        return '/feed';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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
            builder: (context, state) =>
                EchoDetailScreen(echoId: state.pathParameters['id']!),
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
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/verify-identity',
        builder: (context, state) => const IdentityVerificationScreen(),
      ),
    ],
  );
}
