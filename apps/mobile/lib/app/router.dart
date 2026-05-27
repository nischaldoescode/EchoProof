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
import '../features/echo/presentation/screens/proof_trail_screen.dart';
import '../features/echo/presentation/screens/echo_video_screen.dart';
import '../features/echo/presentation/screens/discover_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/notifications/presentation/screens/notifications_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/rooms/presentation/screens/rooms_screen.dart';
import '../features/rooms/presentation/screens/secure_room_chat_screen.dart';
import '../features/subscription/presentation/screens/subscribe_screen.dart';
import '../features/auth/presentation/services/auth_service.dart';
import '../features/onboarding/presentation/services/onboarding_service.dart';
import '../features/subscription/presentation/services/subscription_service.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/echo/presentation/screens/echo_replies_screen.dart';
import '../core/utils/logger.dart';
import '../features/subscription/presentation/screens/purchase_history_screen.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';

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

String? _secureRoomKeyFromUri(Uri uri) {
  final queryKey = uri.queryParameters['key'];
  if (queryKey != null && queryKey.trim().isNotEmpty) {
    return queryKey;
  }
  final fragment = uri.fragment.trim();
  if (fragment.isEmpty) return null;
  try {
    final normalized =
        fragment.startsWith('?') ? fragment.substring(1) : fragment;
    return Uri.splitQueryString(normalized)['key'];
  } catch (_) {
    return null;
  }
}

CustomTransitionPage<void> _profilePage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 230),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(curve),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curve),
            child: child,
          ),
        ),
      );
    },
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

bool _isOnboardingRoute(String location) {
  const routes = [
    '/onboarding',
    '/age-gender',
    '/permissions',
    '/verify-email'
  ];
  return routes.any((r) => location.startsWith(r));
}

GoRouter createRouter({
  required AuthService authService,
  required OnboardingService onboardingService,
  required SubscriptionService subscriptionService,
}) {
  return GoRouter(
    navigatorKey: HyperSnackbar.navigatorKey,
    initialLocation: '/splash',
    refreshListenable: _RouterRefreshStream([authService, onboardingService]),
    redirect: (context, state) async {
      final isLoggedIn = authService.isLoggedIn;
      final location = state.matchedLocation;

      AppLogger.info('router: check — loggedIn=$isLoggedIn loc=$location');

      // Splash handles its own navigation — never redirect it.
      if (location == '/splash') return null;

      // Not logged in: only allow login and email verify routes.
      if (!isLoggedIn) {
        if (location == '/login' || location.startsWith('/verify-email')) {
          return null;
        }
        return '/login';
      }

      // Check username/onboarding status if we don't have it yet.
      if (!authService.hasUsernameChecked) {
        await authService.checkUsername();
      }

      final hasUsername = authService.hasUsername;
      final needsAgeGender = authService.needsAgeGender;

      // Hive onboarding completion  only trust it if hasUsername is also true.
      // A stale Hive "done" with no username = first-time user, ignore the Hive flag.
      final isHiveDone = onboardingService.isComplete() && hasUsername;

      AppLogger.info(
        'router: hasUsername=$hasUsername needsAge=$needsAgeGender hiveDone=$isHiveDone loc=$location',
      );

      // Logged in, onboarding complete
      // User has a username and Hive confirms done → they belong in the main app.
      if (hasUsername && isHiveDone) {
        // Pull them out of any onboarding route back to feed.
        if (_isOnboardingRoute(location)) {
          AppLogger.info('router: onboarding done, redirecting to feed');
          return '/feed';
        }
        // Redirect login/splash to feed.
        if (location == '/login' || location == '/splash') {
          return '/feed';
        }
        // Anywhere else in the main app: let them stay.
        return null;
      }

      // Logged in, username exists but Hive not marked done
      // DB says they have a username but Hive was cleared (e.g. reinstall).
      // Mark Hive as done and let them through.
      if (hasUsername && !isHiveDone) {
        onboardingService.complete();
        if (location == '/login' ||
            location == '/splash' ||
            _isOnboardingRoute(location)) {
          AppLogger.info('router: has username but Hive stale, going to feed');
          return '/feed';
        }
        return null;
      }

      // --- Logged in, no username (new user or mid-onboarding) ---
      // From here: hasUsername=false. They need to complete onboarding.

      // If they're already on an onboarding route, let them stay there.
      // Never redirect someone mid-onboarding back to the start.
      if (needsAgeGender && location != '/age-gender') {
        AppLogger.info('router: new user needs age-gender');
        return '/age-gender';
      }

      if (_isOnboardingRoute(location)) {
        AppLogger.info('router: on onboarding route, staying put');
        return null;
      }

      // Age/gender done but no username yet → onboarding flow.
      AppLogger.info('router: no username → onboarding');
      return '/onboarding';
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
                initialContextStance: s.uri.queryParameters['stance'],
                highlightedContextId: s.uri.queryParameters['context'],
              ),
            ),
            routes: [
              GoRoute(
                path: 'proof-trail',
                pageBuilder: (_, s) => _slidePage(
                  ProofTrailScreen(
                    echoId: s.pathParameters['id']!,
                  ),
                ),
              ),
              GoRoute(
                path: 'video',
                pageBuilder: (_, s) => _slidePage(
                  EchoVideoScreen(
                    echoId: s.pathParameters['id']!,
                    videoUrl: s.uri.queryParameters['url'] ?? '',
                  ),
                ),
              ),
            ],
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
            echoAuthorAvatarUrl: s.uri.queryParameters['avatar'],
            echoAuthorId: s.uri.queryParameters['authorId'],
          ),
        ),
      ),
      GoRoute(
        path: '/discover',
        builder: (_, __) => const DiscoverScreen(),
      ),
      GoRoute(
        path: '/search',
        pageBuilder: (_, s) => _slidePage(
          SearchScreen(initialQuery: s.uri.queryParameters['q']),
        ),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (_, __) => _profilePage(const ProfileScreen()),
      ),
      GoRoute(
        path: '/profile/:username',
        pageBuilder: (_, s) => _profilePage(
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
        path: '/rooms',
        pageBuilder: (_, s) => _slidePage(
          RoomsScreen(
            initialInviteCode: s.uri.queryParameters['code'],
            initialRoomKey: _secureRoomKeyFromUri(s.uri),
          ),
        ),
      ),
      GoRoute(
        path: '/rooms/:id',
        pageBuilder: (_, s) => _slidePage(
          SecureRoomChatScreen(roomId: s.pathParameters['id']!),
        ),
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
        path: '/purchase-history',
        pageBuilder: (_, __) => _slidePage(const PurchaseHistoryScreen()),
      ),
    ],
  );
}
