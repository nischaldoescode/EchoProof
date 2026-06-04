// main
// @params none

import 'dart:async';

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
import 'core/network/certificate_pinning.dart';
import 'core/security/device_security.dart';
import 'core/security/device_security_gate.dart';
import 'core/security/secure_screen.dart';
import 'core/services/ad_service.dart';
import 'core/services/account_device_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/utils/logger.dart';
import 'core/utils/snack.dart';
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

  // initialize firebase first required before any firebase service
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // suppress all debug prints in release
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // block rooted devices in release mode
  if (DeviceSecurity.isCompromised && kReleaseMode) {
    runApp(const SecurityWarningApp());
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
    httpClient: createPinnedClient(),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: false,
      // this app owns deep-link routing below, then hands auth links to supabase
      // keep echoproof://auth-callback and optional https fallbacks in
      // supabase auth -> url configuration -> redirect urls
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
  final accountDeviceService = AccountDeviceService();

  await authService.checkUsername();
  // pre-load notification count for badge
  if (authService.isLoggedIn) {
    notificationService.loadNotifications();
    notificationService.startRealtime();
    unawaited(_startPushIfEnabled());
  }

  final router = createRouter(
    authService: authService,
    onboardingService: onboardingService,
    subscriptionService: subscriptionService,
  );

  var wasLoggedIn = authService.isLoggedIn;
  if (wasLoggedIn) {
    adService.onUserLoggedIn();
    unawaited(_registerAccountDevice(
      accountDeviceService,
      authService,
      router,
    ));
  }

  // notify ad service when user logs in or out
  authService.addListener(() {
    final isLoggedIn = authService.isLoggedIn;
    if (isLoggedIn && !wasLoggedIn) {
      adService.onUserLoggedIn();
      notificationService.loadNotifications();
      notificationService.startRealtime();
      unawaited(_startPushIfEnabled());
      unawaited(_registerAccountDevice(
        accountDeviceService,
        authService,
        router,
      ));
      final pending = _pendingDeepLinkLocation;
      if (pending != null && authService.hasUsername) {
        _pendingDeepLinkLocation = null;
        Future.delayed(const Duration(milliseconds: 250), () {
          _safeGo(router, pending);
        });
      }
    } else if (!isLoggedIn && wasLoggedIn) {
      adService.onUserLoggedOut();
      notificationService.stopRealtime();
      accountDeviceService.stopRealtime();
      unawaited(PushNotificationService.instance.removeToken());
    }
    wasLoggedIn = isLoggedIn;
  });

  // handle notification taps
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final route = message.data['route'] as String?;
    final type = message.data['type'] as String?;

    if (type == 'identity_verified') {
      authService.checkUsername();
    }

    // if account was deleted by admin, sign out immediately
    if (type == 'account_deleted' ||
        message.notification?.title == 'Account deleted') {
      authService.signOut(enforceCooldown: false).then((_) {
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

  // foreground link
  appLinks.uriLinkStream.listen((uri) {
    _handleDeepLink(uri, router, authService);
  });
  // handle notification tap from terminated state
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message == null) return;
    final route = message.data['route'] as String?;
    final type = message.data['type'] as String?;

    // account deleted by admin sign out on cold start
    if (type == 'account_deleted') {
      Future.delayed(const Duration(milliseconds: 300), () {
        authService
            .signOut(enforceCooldown: false)
            .then((_) => router.go('/login'));
      });
      return;
    }

    if (route != null && route.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        router.push(route);
      });
    }
  });

// handle foreground messages (app is open when deletion notification arrives)
  FirebaseMessaging.onMessage.listen((message) {
    final type = message.data['type'] as String?;
    if (type == 'account_deleted') {
      // sign out immediately without waiting for user action
      authService.signOut(enforceCooldown: false).then((_) {
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
          ChangeNotifierProvider<AccountDeviceService>.value(
            value: accountDeviceService,
          ),
        ],
        child: DeviceSecurityGate(
          child: EchoProofApp(router: router),
        ),
      ),
    ),
  );

  if (initialUri != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        _handleDeepLink(initialUri, router, authService);
      });
    });
  }
}

String? _lastHandledLink;
DateTime? _lastHandledLinkAt;
String? _pendingDeepLinkLocation;

Future<void> _startPushIfEnabled() async {
  try {
    final box = Hive.box('app_settings');
    final enabled = box.get('push_enabled', defaultValue: true) as bool;
    if (!enabled) return;
    await PushNotificationService.instance.initialize();
  } catch (e) {
    AppLogger.warn('fcm: startup initialization skipped $e');
  }
}

Future<void> _registerAccountDevice(
  AccountDeviceService deviceService,
  AuthService authService,
  GoRouter router,
) async {
  try {
    await deviceService.register();
    await deviceService.startRealtime(authService, router);
  } on AccountDeviceConflict catch (conflict) {
    final context = HyperSnackbar.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      AppLogger.warn('device-session: conflict but no context available');
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Account active elsewhere'),
        content: Text(
          '${conflict.message}\n\nCurrent device: ${conflict.currentDevice.deviceName}\n\nContinuing here will log out that device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue here'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (proceed == true) {
      await deviceService.register(force: true);
      await deviceService.startRealtime(authService, router);
      if (!context.mounted) return;
      showInfoSnack(context, 'This device is now the active session.');
    } else {
      await authService.signOut(enforceCooldown: false);
      router.go('/login');
    }
  } catch (e) {
    AppLogger.warn('device-session: registration skipped $e');
  }
}

// maps supported app links to internal routes
void _handleDeepLink(Uri uri, GoRouter router, [AuthService? auth]) {
  final link = uri.toString();

  final now = DateTime.now();
  if (_lastHandledLink == link &&
      _lastHandledLinkAt != null &&
      now.difference(_lastHandledLinkAt!) < const Duration(seconds: 2)) {
    return;
  }
  _lastHandledLink = link;
  _lastHandledLinkAt = now;

  if (_isSupabaseAuthLink(uri)) {
    AppLogger.info('deep link: auth callback received');
    if (auth != null) {
      unawaited(_completeAuthCallback(uri, router, auth));
    }
    return;
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (uri.scheme == 'echoproof') {
    if (uri.host == 'room' && (segments.isEmpty || segments.first == 'join')) {
      _safeGo(router, _roomInviteLocation(uri), auth: auth);
      return;
    }

    if (uri.host == 'echo' && segments.isNotEmpty) {
      _safeGo(
        router,
        '/feed/echo/${Uri.encodeComponent(segments.first)}',
        auth: auth,
      );
      return;
    }

    if (uri.host == 'user' && segments.isNotEmpty) {
      _safeGo(
        router,
        '/profile/${Uri.encodeComponent(segments.first)}',
        auth: auth,
      );
      return;
    }
  }

  // https app links
  if (uri.scheme == 'https' &&
      (uri.host == 'join.echoproof.online' ||
          uri.host == 'www.join.echoproof.online') &&
      (segments.isEmpty || segments.first == 'room')) {
    _safeGo(router, _roomInviteLocation(uri), auth: auth);
    return;
  }

  if (uri.scheme == 'https' &&
      (uri.host == 'echoproof.online' || uri.host == 'www.echoproof.online')) {
    if (segments.isNotEmpty && segments.first == 'room') {
      _safeGo(router, _roomInviteLocation(uri), auth: auth);
      return;
    }
    if (segments.length >= 2 && (segments[0] == 'echo' || segments[0] == 'e')) {
      _safeGo(
        router,
        '/feed/echo/${Uri.encodeComponent(segments[1])}',
        auth: auth,
      );
      return;
    }
    if (segments.length >= 2 && (segments[0] == 'user' || segments[0] == 'u')) {
      _safeGo(
        router,
        '/profile/${Uri.encodeComponent(segments[1])}',
        auth: auth,
      );
      return;
    }
  }
}

String _roomInviteLocation(Uri uri) {
  final fragmentParams = uri.fragment.isEmpty
      ? const <String, String>{}
      : Uri.splitQueryString(uri.fragment);
  final code = uri.queryParameters['code'] ?? fragmentParams['code'] ?? '';
  final key = uri.queryParameters['key'] ?? fragmentParams['key'] ?? '';
  final query = {
    if (code.isNotEmpty) 'code': code,
    if (key.isNotEmpty) 'key': key,
  };
  return Uri(path: '/rooms', queryParameters: query.isEmpty ? null : query)
      .toString();
}

void _safeGo(GoRouter router, String location, {AuthService? auth}) {
  if (auth != null && !auth.isLoggedIn) {
    _pendingDeepLinkLocation = location;
    router.go('/login');
    return;
  }

  try {
    router.go(location);
  } on GoException catch (e) {
    AppLogger.warn('deep link: route failed for $location: $e');
    router.go('/feed');
  } catch (e) {
    AppLogger.warn('deep link: route failed for $location: $e');
    router.go('/feed');
  }
}

Future<void> _completeAuthCallback(
  Uri uri,
  GoRouter router,
  AuthService auth,
) async {
  final success = await auth.handleAuthCallback(uri);
  if (!success) {
    router.go('/login');
    return;
  }

  if (auth.hasUsername) {
    final pending = _pendingDeepLinkLocation;
    if (pending != null) {
      _pendingDeepLinkLocation = null;
      _safeGo(router, pending);
    } else {
      router.go('/feed');
    }
  } else if (auth.needsAgeGender) {
    router.go('/age-gender');
  } else {
    router.go('/onboarding');
  }
}

bool _isSupabaseAuthLink(Uri uri) {
  final isCustomAuth = uri.scheme == 'echoproof' && uri.host == 'auth-callback';
  final isHttpsAuth = uri.scheme == 'https' &&
      (uri.host == 'echoproof.online' || uri.host == 'www.echoproof.online') &&
      ((uri.pathSegments.length == 1 &&
              uri.pathSegments[0] == 'auth-callback') ||
          (uri.pathSegments.length >= 2 &&
              uri.pathSegments[0] == 'auth' &&
              uri.pathSegments[1] == 'callback'));
  final hasAuthPayload = uri.queryParameters.containsKey('code') ||
      uri.queryParameters.containsKey('token_hash') ||
      uri.queryParameters.containsKey('error_description') ||
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

class SecurityWarningApp extends StatelessWidget {
  const SecurityWarningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: HyperSnackbar.navigatorKey,
      home: const SecureScreen(child: SecurityLockdownScreen()),
    );
  }
}
