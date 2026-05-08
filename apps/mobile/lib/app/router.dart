import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import '../features/auth/presentation/screens/splash_screen.dart'
    show SplashScreen;
import '../features/auth/presentation/screens/login_screen.dart'
    show LoginScreen;
import '../features/auth/presentation/screens/otp_screen.dart';
import '../features/auth/presentation/screens/permissions_screen.dart';
import '../features/auth/presentation/screens/age_gender_screen.dart';
import '../features/auth/presentation/screens/identity_verification_screen.dart';
import '../features/onboarding/presentation/screens/onboarding_root.dart';
import '../features/echo/presentation/screens/feed_screen.dart';
import '../features/echo/presentation/screens/create_echo_screen.dart';
import '../features/echo/presentation/screens/echo_detail_screen.dart';
import '../features/echo/presentation/screens/discover_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/subscription/presentation/screens/subscribe_screen.dart';
import '../features/auth/presentation/services/auth_service.dart';
import '../features/onboarding/presentation/services/onboarding_service.dart';
import '../features/subscription/presentation/services/subscription_service.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/echo/presentation/screens/echo_replies_screen.dart';
import '../core/utils/logger.dart';

CustomTransitionPage<void> _slidePage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: const Interval(0, 0.5)),
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.04, 0),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 280),
  );
}

class _RouterRefreshStream extends ChangeNotifier {
  bool _pending = false;

  _RouterRefreshStream(List<Listenable> notifiers) {
    for (final n in notifiers) {
      n.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (_pending) return;
    _pending = true;
    // Debounce: collapse multiple rapid notifyListeners into one redirect.
    Future.microtask(() {
      _pending = false;
      notifyListeners();
    });
  }
}

GoRouter createRouter({
  required AuthService authService,
  required OnboardingService onboardingService,
  required SubscriptionService subscriptionService,
}) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _RouterRefreshStream([authService, onboardingService]),
    redirect: (context, state) async {
      final isLoggedIn = authService.isLoggedIn;
      final location = state.matchedLocation;

      AppLogger.info(
          'router: redirect check — isLoggedIn=$isLoggedIn location=$location');

      if (location == '/splash') return null;

      if (!isLoggedIn) {
        if (location == '/login' || location == '/verify-email') return null;
        return '/login';
      }

      const onboardingRoutes = [
        '/onboarding',
        '/age-gender',
        '/permissions',
        '/verify-email',
      ];

      final isOnboardingRoute =
          onboardingRoutes.any((r) => location.startsWith(r));

      // If Hive says onboarding is complete, trust it while on onboarding
      // routes — this prevents a loop when the DB write succeeded partially
      // or the trigger is delayed. The feed will do a real check independently.
      if (isOnboardingRoute && onboardingService.isComplete()) {
        AppLogger.info('router: onboarding done per Hive, going to feed');
        return '/feed';
      }

      // Only hit the DB when we genuinely need fresh state:
      // first check after login, or when coming from an auth screen.
      final needsDbCheck = (!authService.hasUsernameChecked ||
              location == '/login' ||
              location == '/splash') &&
          location != '/onboarding';

      if (needsDbCheck) {
        await authService.checkUsername();
      }

      final hasUsername = authService.hasUsername;
      final isOnboardingDone = onboardingService.isComplete();

      AppLogger.info(
          'router: after check — hasUsername=$hasUsername isOnboardingDone=$isOnboardingDone');

      if (!hasUsername) {
        if (isOnboardingRoute) return null;
        AppLogger.info('router: no username, redirecting to onboarding');
        return '/onboarding';
      }

      if (hasUsername && !isOnboardingDone) {
        onboardingService.complete();
      }

      if (hasUsername && (location == '/login' || location == '/splash')) {
        return '/feed';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, __) => _slidePage(const SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, __) => _slidePage(const LoginScreen()),
      ),
      GoRoute(
        path: '/verify-email',
        pageBuilder: (_, s) =>
            _slidePage(OtpScreen(email: s.extra as String? ?? '')),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, __) => _slidePage(const OnboardingRoot()),
      ),
      GoRoute(
        path: '/age-gender',
        pageBuilder: (_, s) => _slidePage(
          AgeGenderScreen(email: s.extra as String? ?? ''),
        ),
      ),
      GoRoute(
        path: '/permissions',
        pageBuilder: (_, __) => _slidePage(const PermissionsScreen()),
      ),
      GoRoute(
        path: '/feed',
        builder: (_, __) => const FeedScreen(),
        routes: [
          GoRoute(
            path: 'echo/:id',
            pageBuilder: (_, s) => _slidePage(
              EchoDetailScreen(
                echoId: s.pathParameters['id']!,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/create',
        pageBuilder: (_, __) => _slidePage(const CreateEchoScreen()),
      ),
      GoRoute(
        path: '/echo/:id/replies',
        pageBuilder: (_, s) => _slidePage(
          EchoRepliesScreen(
            echoId: s.pathParameters['id']!,
            echoAuthorUsername: s.uri.queryParameters['author'] ?? '',
            echoContent: s.uri.queryParameters['content'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/discover',
        builder: (_, __) => const DiscoverScreen(),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (_, __) => _slidePage(const SearchScreen()),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/profile/:username',
        pageBuilder: (_, s) => _slidePage(
          ProfileScreen(
            username: s.pathParameters['username'],
          ),
        ),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, __) => _slidePage(const NotificationsScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, __) => _slidePage(const SettingsScreen()),
      ),
      GoRoute(
        path: '/subscribe',
        pageBuilder: (_, __) => _slidePage(const SubscribeScreen()),
      ),
      GoRoute(
        path: '/verify-identity',
        pageBuilder: (_, __) => _slidePage(const IdentityVerificationScreen()),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => OtpScreen(
          email: state.extra as String? ?? '',
        ),
      ),
      GoRoute(
        path: '/onboarding-age-gender',
        builder: (context, state) => const AgeGenderScreen(),
      ),
      GoRoute(
        path: '/permissions',
        builder: (context, state) => const PermissionsScreen(),
      ),
      GoRoute(path: '/subscribe', builder: (_, __) => const SubscribeScreen()),
    ],
  );
}
