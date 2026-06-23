// app router
// @params child supplies the page widget for custom transitions

import 'dart:math' as math;
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
import '../features/echo/presentation/screens/echo_signal_game_screen.dart';
import '../features/echo/presentation/screens/bookmarks_screen.dart';
import '../features/echo/presentation/screens/proof_trail_screen.dart';
import '../features/echo/presentation/screens/echo_video_screen.dart';
import '../features/echo/presentation/screens/discover_screen.dart';
import '../features/profile/presentation/screens/profile_screen.dart';
import '../features/profile/presentation/screens/analytics_tab.dart'
    show ProfileAnalyticsScreen;
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
import '../core/utils/snack.dart';
import '../features/subscription/presentation/screens/purchase_history_screen.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';

CustomTransitionPage<void> _slidePage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final textDirection = Directionality.of(context);
      final directionSign = textDirection == TextDirection.rtl ? -1.0 : 1.0;

      // route motion is fixed in logical pixels instead of a child-size
      // fraction. this prevents small jumps when split screen, keyboard
      // insets, or dynamic content change the route size mid-transition.
      return RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final raw = animation.value.clamp(0.0, 1.0).toDouble();
            final fade = Curves.easeOutCubic.transform(raw);

            if (reduceMotion) {
              return Opacity(opacity: fade, child: child);
            }

            final eased = Curves.easeOutCubic.transform(raw);
            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            final offset = (1 - eased) * 18 * directionSign;
            final snappedOffset =
                (offset * devicePixelRatio).roundToDouble() / devicePixelRatio;

            return Opacity(
              opacity: fade,
              child: Transform.translate(
                offset: Offset(snappedOffset, 0),
                child: child,
              ),
            );
          },
        ),
      );
    },
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
    final normalized = fragment.startsWith('?')
        ? fragment.substring(1)
        : fragment;
    return Uri.splitQueryString(normalized)['key'];
  } catch (_) {
    return null;
  }
}

CustomTransitionPage<void> _profilePage(Widget child) {
  return _slidePage(child);
}

CustomTransitionPage<void> _signalDriftPage(GoRouterState state) {
  final origin = state.extra is Offset ? state.extra as Offset : null;
  return CustomTransitionPage<void>(
    child: const EchoSignalGameScreen(),
    opaque: false,
    transitionDuration: const Duration(milliseconds: 580),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      if (reduceMotion) {
        return FadeTransition(opacity: animation, child: child);
      }

      final screen = MediaQuery.sizeOf(context);
      final padding = MediaQuery.paddingOf(context);
      final fallback = Offset(screen.width * 0.18, padding.top + 28);
      final revealOrigin = origin ?? fallback;
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInQuart,
      );

      return AnimatedBuilder(
        animation: curve,
        builder: (context, _) {
          final value = curve.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              ClipPath(
                clipper: _SignalDriftRevealClipper(
                  origin: revealOrigin,
                  progress: value,
                ),
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0.9, end: 1).animate(curve),
                  child: Transform.scale(
                    scale: 0.985 + value * 0.015,
                    child: child,
                  ),
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: _SignalDriftRevealPainter(
                    origin: revealOrigin,
                    progress: value,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SignalDriftRevealPainter extends CustomPainter {
  const _SignalDriftRevealPainter({
    required this.origin,
    required this.progress,
  });

  final Offset origin;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final safeOrigin = Offset(
      origin.dx.clamp(0, size.width).toDouble(),
      origin.dy.clamp(0, size.height).toDouble(),
    );
    final maxRadius = _maxRadiusFor(size, safeOrigin);
    final eased = Curves.easeOutCubic.transform(progress.clamp(0, 1));
    final radius = 10 + maxRadius * eased;
    final visible = (1 - progress).clamp(0, 1).toDouble();
    final accent = const Color(0xFF2F6F5A);

    if (visible <= 0) return;

    final fill = Paint()
      ..color = accent.withValues(alpha: 0.08 * visible)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(safeOrigin, radius * 0.52, fill);

    final ring = Paint()
      ..color = accent.withValues(alpha: 0.28 * visible)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 - (7 * progress.clamp(0, 1));
    canvas.drawCircle(safeOrigin, radius, ring);

    if (progress < 0.45) {
      final pulse = Paint()
        ..color = accent.withValues(alpha: 0.14 * (1 - progress / 0.45))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(safeOrigin, radius * 1.18, pulse);
    }
  }

  double _maxRadiusFor(Size size, Offset point) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    return corners
        .map((corner) => (corner - point).distance)
        .fold<double>(0, math.max);
  }

  @override
  bool shouldRepaint(covariant _SignalDriftRevealPainter oldDelegate) {
    return origin != oldDelegate.origin || progress != oldDelegate.progress;
  }
}

class _SignalDriftRevealClipper extends CustomClipper<Path> {
  const _SignalDriftRevealClipper({
    required this.origin,
    required this.progress,
  });

  final Offset origin;
  final double progress;

  @override
  Path getClip(Size size) {
    final safeOrigin = Offset(
      origin.dx.clamp(0, size.width).toDouble(),
      origin.dy.clamp(0, size.height).toDouble(),
    );
    final maxRadius = _maxRadiusFor(size, safeOrigin);
    final eased = Curves.easeOutCubic.transform(progress.clamp(0, 1));
    final radius = 6 + maxRadius * eased;
    return Path()..addOval(Rect.fromCircle(center: safeOrigin, radius: radius));
  }

  double _maxRadiusFor(Size size, Offset point) {
    final corners = [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    return corners
        .map((corner) => (corner - point).distance)
        .fold<double>(0, math.max);
  }

  @override
  bool shouldReclip(covariant _SignalDriftRevealClipper oldClipper) {
    return origin != oldClipper.origin || progress != oldClipper.progress;
  }
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
    // debounce rapid notifylisteners into one redirect
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
    '/verify-email',
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
    observers: [RouteScopedSnackObserver()],
    redirect: (context, state) async {
      final isLoggedIn = authService.isLoggedIn;
      final location = state.matchedLocation;

      AppLogger.info('router: check — loggedIn=$isLoggedIn loc=$location');

      // splash handles its own navigation
      if (location == '/splash') return null;

      // signed-out users can only reach auth routes
      if (!isLoggedIn) {
        if (location == '/login' || location.startsWith('/verify-email')) {
          return null;
        }
        return '/login';
      }

      // check username status once before redirecting
      if (!authService.hasUsernameChecked) {
        await authService.checkUsername();
      }

      final hasUsername = authService.hasUsername;
      final needsAgeGender = authService.needsAgeGender;

      // hive completion is valid only when the profile has a username
      // stale hive state after reinstall should not skip onboarding
      final isHiveDone = onboardingService.isComplete() && hasUsername;

      AppLogger.info(
        'router: hasUsername=$hasUsername needsAge=$needsAgeGender hiveDone=$isHiveDone loc=$location',
      );

      // signed-in user has completed onboarding
      if (hasUsername && isHiveDone) {
        // return completed users from onboarding to feed
        if (_isOnboardingRoute(location)) {
          AppLogger.info('router: onboarding done, redirecting to feed');
          return '/feed';
        }
        // auth entry routes should not stay visible after login
        if (location == '/login' || location == '/splash') {
          return '/feed';
        }
        // keep users on the current app route
        return null;
      }

      // profile exists but local onboarding state was cleared
      // this usually happens after reinstall or local data reset
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

      // signed-in user still needs onboarding

      // age and gender are required before username setup
      if (needsAgeGender && location != '/age-gender') {
        AppLogger.info('router: new user needs age-gender');
        return '/age-gender';
      }

      // keep users on their current onboarding step
      if (_isOnboardingRoute(location)) {
        AppLogger.info('router: on onboarding route, staying put');
        return null;
      }

      // age and gender are done so continue to username onboarding
      AppLogger.info('router: no username → onboarding');
      return '/onboarding';
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, _) => _slidePage(const SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, _) => _slidePage(const LoginScreen()),
      ),
      GoRoute(
        path: '/verify-email',
        pageBuilder: (_, s) =>
            _slidePage(OtpScreen(email: s.extra as String? ?? '')),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, _) => _slidePage(const OnboardingRoot()),
      ),
      GoRoute(
        path: '/age-gender',
        pageBuilder: (_, s) =>
            _slidePage(AgeGenderScreen(email: s.extra as String? ?? '')),
      ),
      GoRoute(
        path: '/permissions',
        pageBuilder: (_, _) => _slidePage(const PermissionsScreen()),
      ),
      GoRoute(
        path: '/feed',
        builder: (_, _) => const FeedScreen(),
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
                  ProofTrailScreen(echoId: s.pathParameters['id']!),
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
        path: '/echo/:id',
        redirect: (_, s) {
          final id = s.pathParameters['id']!;
          final query = s.uri.hasQuery ? '?${s.uri.query}' : '';
          return '/feed/echo/${Uri.encodeComponent(id)}$query';
        },
      ),
      GoRoute(
        path: '/e/:id',
        redirect: (_, s) {
          final id = s.pathParameters['id']!;
          final query = s.uri.hasQuery ? '?${s.uri.query}' : '';
          return '/feed/echo/${Uri.encodeComponent(id)}$query';
        },
      ),
      GoRoute(
        path: '/create',
        pageBuilder: (_, _) => _slidePage(const CreateEchoScreen()),
      ),
      GoRoute(
        path: '/signal-drift',
        pageBuilder: (_, s) => _signalDriftPage(s),
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
      GoRoute(path: '/discover', builder: (_, _) => const DiscoverScreen()),
      GoRoute(
        path: '/search',
        pageBuilder: (_, s) =>
            _slidePage(SearchScreen(initialQuery: s.uri.queryParameters['q'])),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (_, _) => _profilePage(const ProfileScreen()),
      ),
      GoRoute(
        path: '/profile/bookmarks',
        pageBuilder: (_, _) => _profilePage(const BookmarksScreen()),
      ),
      GoRoute(
        path: '/profile/analytics',
        pageBuilder: (_, _) => _profilePage(const ProfileAnalyticsScreen()),
      ),
      GoRoute(
        path: '/profile/:username/follows',
        pageBuilder: (_, s) => _profilePage(
          ProfileFollowsScreen(
            username: s.pathParameters['username']!,
            initialMode: s.uri.queryParameters['tab'] ?? 'followers',
          ),
        ),
      ),
      GoRoute(
        path: '/profile/:username',
        pageBuilder: (_, s) =>
            _profilePage(ProfileScreen(username: s.pathParameters['username'])),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (_, _) => _slidePage(const NotificationsScreen()),
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
        pageBuilder: (_, s) =>
            _slidePage(SecureRoomChatScreen(roomId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, _) => _slidePage(const SettingsScreen()),
      ),
      GoRoute(
        path: '/subscribe',
        pageBuilder: (_, _) => _slidePage(const SubscribeScreen()),
      ),
      GoRoute(
        path: '/verify-identity',
        pageBuilder: (_, _) => _slidePage(const IdentityVerificationScreen()),
      ),
      GoRoute(
        path: '/purchase-history',
        pageBuilder: (_, _) => _slidePage(const PurchaseHistoryScreen()),
      ),
    ],
  );
}
