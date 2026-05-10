import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';
import 'app/app.dart';
import 'app/router.dart';
import 'core/security/device_security.dart';
import 'core/services/ad_service.dart';
import 'core/utils/logger.dart';
import 'features/auth/presentation/services/auth_service.dart';
import 'features/onboarding/presentation/services/onboarding_service.dart';
import 'features/echo/presentation/services/echo_feed_service.dart';
import 'features/echo/presentation/services/create_echo_service.dart';
import 'features/notifications/presentation/services/notification_service.dart';
import 'features/subscription/presentation/services/subscription_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_portal/flutter_portal.dart';
import 'core/services/connectivity_service.dart';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // initialize firebase first — required before any Firebase service
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // suppress all debug prints in release
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // block rooted devices in release mode
  if (DeviceSecurity.isCompromised && kReleaseMode) {
    runApp(const _SecurityWarningApp());
    return;
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  await Hive.initFlutter();
  await Hive.openBox('app_settings');
  await Hive.openBox('echo_cache');
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      // The redirect URL that Supabase uses in magic link emails.
      // This must match what's registered in Supabase Auth → URL Configuration → Redirect URLs.
    ),
  );

  AppLogger.info('main: supabase initialized');
  await ConnectivityService.instance.initialize();

  final authService = AuthService();
  final onboardingService = OnboardingService();
  final echoFeedService = EchoFeedService();
  final createEchoService = CreateEchoService();
  final notificationService = NotificationService();
  final subscriptionService = SubscriptionService();
  final adService = AdService();

  await authService.checkUsername();
  // pre-load notification count for badge
  if (authService.isLoggedIn) {
    notificationService.loadNotifications();
    notificationService.startRealtime();
  }

  final router = createRouter(
    authService: authService,
    onboardingService: onboardingService,
    subscriptionService: subscriptionService,
  );

  // notify ad service when user logs in or out
  authService.addListener(() {
    if (authService.isLoggedIn) {
      adService.onUserLoggedIn();
      notificationService.loadNotifications();
      notificationService.startRealtime();
    } else {
      adService.onUserLoggedOut();
      notificationService.stopRealtime();
    }
  });

  // handle notification taps
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final route = message.data['route'] as String?;
    final type = message.data['type'] as String?;

    if (type == 'identity_verified') {
      authService.checkUsername();
    }

    // If account was deleted by admin, sign out immediately.
    if (type == 'account_deleted' ||
        message.notification?.title == 'Account deleted') {
      authService.signOut().then((_) {
        router.go('/login');
      });
      return;
    }

    if (route != null && route.isNotEmpty) {
      router.push(route);
    }
  });
  // handle app links for echo, profile, and auth callbacks
  final appLinks = AppLinks();

  // cold start link
  final initialUri = await appLinks.getInitialLink();
  if (initialUri != null) {
    _handleDeepLink(initialUri, router, authService);
  }

  // foreground link
  appLinks.uriLinkStream.listen((uri) {
    _handleDeepLink(uri, router, authService);
  });
  // handle notification tap from terminated state
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message == null) return;
    final route = message.data['route'] as String?;
    final type = message.data['type'] as String?;

    // Account deleted by admin — sign out on cold start.
    if (type == 'account_deleted') {
      Future.delayed(const Duration(milliseconds: 300), () {
        authService.signOut().then((_) => router.go('/login'));
      });
      return;
    }

    if (route != null && route.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        router.push(route);
      });
    }
  });

// Handle foreground messages (app is open when deletion notification arrives).
  FirebaseMessaging.onMessage.listen((message) {
    final type = message.data['type'] as String?;
    if (type == 'account_deleted') {
      // Sign out immediately without waiting for user action.
      authService.signOut().then((_) {
        router.go('/login');
      });
    }
  });
  final lifecycleObserver = _AppLifecycleObserver(subscriptionService);
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  runApp(
    Portal(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<OnboardingService>.value(
              value: onboardingService),
          ChangeNotifierProvider<EchoFeedService>.value(value: echoFeedService),
          ChangeNotifierProvider<CreateEchoService>.value(
              value: createEchoService),
          ChangeNotifierProvider<NotificationService>.value(
              value: notificationService),
          ChangeNotifierProvider<SubscriptionService>.value(
              value: subscriptionService),
          ChangeNotifierProvider<AdService>.value(value: adService),
        ],
        child: EchoProofApp(router: router),
      ),
    ),
  );
}

String? _lastHandledLink;

// maps supported app links to internal routes
void _handleDeepLink(Uri uri, GoRouter router, [AuthService? auth]) {
  final link = uri.toString();

  if (_lastHandledLink == link) return;
  _lastHandledLink = link;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (uri.host == 'auth-callback') {
    AppLogger.info('deep link: auth-callback received');
    Future.delayed(const Duration(milliseconds: 500), () async {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && auth != null) {
        await auth.checkUsername();
      }
    });
    return;
  }

  if (uri.scheme == 'echoproof') {
    // Auth callback from OTP email magic link.
    // Supabase sends: echoproof://auth-callback#access_token=...&type=signup
    // or: echoproof://auth-callback?token=...&type=email
    if (uri.host == 'auth-callback') {
      // Supabase flutter SDK handles the session restoration automatically
      // when it detects the fragment. We just need to trigger a router refresh.
      AppLogger.info(
          'deep link: auth-callback received, refreshing auth state');
      // Give Supabase a moment to process the token from the URL fragment.
      Future.delayed(const Duration(milliseconds: 500), () async {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          AppLogger.info('deep link: session restored, checking username');
          // This notifies the router via authService listeners.
          await auth?.checkUsername();
        }
      });
      return;
    }

    if (uri.host == 'echo' && segments.isNotEmpty) {
      router.go('/feed/echo/${segments.first}');
      return;
    }

    if (uri.host == 'user' && segments.isNotEmpty) {
      router.go('/profile/${segments.first}');
      return;
    }
  }

  // https app links
  if (uri.scheme == 'https' &&
      (uri.host == 'echoproof.online' || uri.host == 'www.echoproof.online')) {
    if (segments.length >= 2 && segments[0] == 'echo') {
      router.go('/feed/echo/${segments[1]}');
      return;
    }
    if (segments.length >= 2 && segments[0] == 'user') {
      router.go('/profile/${segments[1]}');
      return;
    }
  }
}

bool _isSupabaseAuthLink(Uri uri) {
  final isCustomAuth = uri.scheme == 'echoproof' && uri.host == 'auth-callback';
  final isHttpsAuth = uri.scheme == 'https' &&
      (uri.host == 'echoproof.online' || uri.host == 'www.echoproof.online') &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments[0] == 'auth' &&
      uri.pathSegments[1] == 'callback';
  final hasAuthPayload = uri.queryParameters.containsKey('code') ||
      uri.fragment.contains('access_token') ||
      uri.fragment.contains('error_description');

  return (isCustomAuth || isHttpsAuth) && hasAuthPayload;
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver(this._sub);
  final SubscriptionService _sub;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sub.checkSubscriptionStatus();
    }
  }
}

class _SecurityWarningApp extends StatelessWidget {
  const _SecurityWarningApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: HyperSnackbar.navigatorKey,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.security_outlined,
                  size: 64,
                  color: Colors.white,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Device not supported',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Echoproof cannot run on rooted or modified devices. This protects the integrity of community verification.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
