// main
// @params none

import 'dart:async';

import 'package:flutter/material.dart';
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
import 'core/services/app_update_service.dart';
import 'core/services/quick_action_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/utils/app_haptics.dart';
import 'core/utils/logger.dart';
import 'core/utils/snack.dart';
import 'features/auth/presentation/services/auth_service.dart';
import 'features/onboarding/presentation/services/onboarding_service.dart';
import 'features/echo/presentation/services/echo_feed_service.dart';
import 'features/echo/presentation/services/bookmark_service.dart';
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
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarDividerColor: Colors.white,
      systemNavigationBarContrastEnforced: true,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
    ),
  );

  // initialize firebase first required before any firebase service
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // suppress all debug prints in release
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  await DeviceSecurity.enforceSecureWindow();

  // block rooted hooked repackaged or sideloaded release builds before app state loads
  final securityReport = await DeviceSecurity.inspect();
  if (securityReport.compromised && kReleaseMode) {
    runApp(const SecurityWarningApp());
    return;
  }

  await Hive.initFlutter();
  await Hive.openBox('app_settings');
  await Hive.openBox('echo_cache');
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
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
  final bookmarkService = BookmarkService();
  final createEchoService = CreateEchoService();
  final notificationService = NotificationService();
  final subscriptionService = SubscriptionService();
  final adService = AdService();
  final accountDeviceService = AccountDeviceService();
  final appUpdateService = AppUpdateService();

  await authService.checkUsername();
  // pre-load notification count for badge
  if (authService.isLoggedIn) {
    notificationService.loadNotifications();
    notificationService.startRealtime();
    unawaited(bookmarkService.loadBookmarks());
    unawaited(_startPushIfEnabled());
  }

  final router = createRouter(
    authService: authService,
    onboardingService: onboardingService,
    subscriptionService: subscriptionService,
  );
  unawaited(
    QuickActionService.attach(
      router,
      profileEnabled: _quickActionsAllowed(authService),
    ),
  );

  var wasLoggedIn = authService.isLoggedIn;
  if (wasLoggedIn) {
    adService.onUserLoggedIn();
    unawaited(
      _registerAccountDevice(accountDeviceService, authService, router),
    );
  }

  // notify ad service when user logs in or out
  authService.addListener(() {
    final isLoggedIn = authService.isLoggedIn;
    if (isLoggedIn && !wasLoggedIn) {
      adService.onUserLoggedIn();
      unawaited(
        QuickActionService.syncForAuth(
          profileEnabled: _quickActionsAllowed(authService),
        ),
      );
      notificationService.loadNotifications();
      notificationService.startRealtime();
      unawaited(bookmarkService.loadBookmarks());
      unawaited(_startPushIfEnabled());
      unawaited(
        _registerAccountDevice(accountDeviceService, authService, router),
      );
      unawaited(_maybeShowAccountRecoveryDialog(authService, router));
      final pending = _pendingDeepLinkLocation;
      if (pending != null && authService.hasUsername) {
        _pendingDeepLinkLocation = null;
        Future.delayed(const Duration(milliseconds: 250), () {
          _safeGo(router, pending);
        });
      }
    } else if (!isLoggedIn && wasLoggedIn) {
      adService.onUserLoggedOut();
      unawaited(QuickActionService.syncForAuth(profileEnabled: false));
      notificationService.stopRealtime();
      bookmarkService.clearForLogout();
      accountDeviceService.stopRealtime();
      unawaited(PushNotificationService.instance.removeToken());
    }
    unawaited(
      QuickActionService.syncForAuth(
        profileEnabled: _quickActionsAllowed(authService),
      ),
    );
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
        message.notification?.title == 'Account deleted' ||
        message.notification?.title == 'Account scheduled for deletion') {
      authService.signOut(enforceCooldown: false).then((_) {
        router.go('/login');
      });
      return;
    }

    if (route != null && route.isNotEmpty) {
      _safeGo(router, route, auth: authService);
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
        _safeGo(router, route, auth: authService);
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
  final lifecycleObserver = _AppLifecycleObserver(
    subscriptionService,
    authService,
    accountDeviceService,
    appUpdateService,
    router,
  );
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  runApp(
    Portal(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
          ChangeNotifierProvider<OnboardingService>.value(
            value: onboardingService,
          ),
          ChangeNotifierProvider<EchoFeedService>.value(value: echoFeedService),
          ChangeNotifierProvider<BookmarkService>.value(value: bookmarkService),
          ChangeNotifierProvider<CreateEchoService>.value(
            value: createEchoService,
          ),
          ChangeNotifierProvider<NotificationService>.value(
            value: notificationService,
          ),
          ChangeNotifierProvider<SubscriptionService>.value(
            value: subscriptionService,
          ),
          ChangeNotifierProvider<AdService>.value(value: adService),
          ChangeNotifierProvider<AccountDeviceService>.value(
            value: accountDeviceService,
          ),
        ],
        child: DeviceSecurityGate(child: EchoProofApp(router: router)),
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

  if (authService.isLoggedIn) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeShowAccountRecoveryDialog(authService, router));
    });
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future.delayed(const Duration(milliseconds: 900), () {
      unawaited(
        appUpdateService.checkForRequiredUpdate(
          reason: AppUpdateCheckReason.launch,
        ),
      );
    });
  });
}

String? _lastHandledLink;
DateTime? _lastHandledLinkAt;
String? _pendingDeepLinkLocation;
bool _accountRecoveryDialogOpen = false;

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
    if (_canAutoRecoverDeviceConflict(conflict)) {
      AppLogger.info(
        'device-session: auto recovering likely reinstall on same device',
      );
      await deviceService.register(force: true);
      await deviceService.startRealtime(authService, router);
      return;
    }

    final context = await _waitForAppContext();
    if (context == null || !context.mounted) {
      AppLogger.warn('device-session: conflict but no context available');
      return;
    }
    if (!authService.isLoggedIn) return;
    final likelySamePhone =
        conflict.sameNamedDevice || conflict.kind == 'possibly_same_device';
    final lastSeen = _formatDeviceConflictSeen(conflict.lastSeenAgeSeconds);
    unawaited(AppHaptics.criticalOpen(key: 'device_conflict_dialog'));
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          likelySamePhone ? 'Confirm this phone' : 'Account active elsewhere',
        ),
        content: Text(
          likelySamePhone
              ? 'This looks like your previous Echoproof install on ${conflict.currentDevice.deviceName}. It was last active $lastSeen.\n\nContinue here only if this is you. The old install will be logged out.'
              : '${conflict.message}\n\nActive device: ${conflict.currentDevice.deviceName}\nLast active: $lastSeen\n\nContinue here only if this is you. The other device will be logged out.',
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

    if (!context.mounted || !authService.isLoggedIn) return;
    if (proceed == true) {
      unawaited(AppHaptics.criticalConfirm(key: 'device_conflict_continue'));
      await deviceService.register(force: true);
      await deviceService.startRealtime(authService, router);
      if (!context.mounted) return;
      showInfoSnack(context, 'This device is now the active session.');
    } else {
      if (proceed != false) return;
      unawaited(AppHaptics.caution(key: 'device_conflict_cancel'));
      await authService.signOut(enforceCooldown: false);
      router.go('/login');
    }
  } catch (e) {
    AppLogger.warn('device-session: registration skipped $e');
  }
}

bool _canAutoRecoverDeviceConflict(AccountDeviceConflict conflict) {
  final age = conflict.lastSeenAgeSeconds;
  if (age == null || age < 120) return false;
  return conflict.kind == 'possibly_same_device' && conflict.sameNamedDevice;
}

Future<BuildContext?> _waitForAppContext({
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final context = HyperSnackbar.navigatorKey.currentContext;
    if (context != null && context.mounted) return context;
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }
  return HyperSnackbar.navigatorKey.currentContext;
}

String _formatDeviceConflictSeen(int? seconds) {
  if (seconds == null || seconds < 0) return 'recently';
  if (seconds < 60) return 'just now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours hr ago';
  final days = hours ~/ 24;
  return '$days day${days == 1 ? '' : 's'} ago';
}

Future<void> _maybeShowAccountRecoveryDialog(
  AuthService authService,
  GoRouter router,
) async {
  if (_accountRecoveryDialogOpen || !authService.isLoggedIn) return;

  await Future<void>.delayed(const Duration(milliseconds: 350));
  if (!authService.isLoggedIn) return;

  await authService.checkUsername();
  if (!authService.hasPendingAccountDeletion || _accountRecoveryDialogOpen) {
    return;
  }

  final context = HyperSnackbar.navigatorKey.currentContext;
  if (context == null || !context.mounted) return;

  _accountRecoveryDialogOpen = true;
  unawaited(AppHaptics.criticalOpen(key: 'account_recovery_dialog'));
  final keepAccount = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Account recovery',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, _, _) {
      final restoreUntil = authService.accountDeletionRestoreUntil;
      final deadline = restoreUntil == null
          ? 'within 7 days'
          : _formatRecoveryDeadline(restoreUntil);

      return SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth > 520
                  ? 440.0
                  : constraints.maxWidth - 32;
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: const Text('Keep your account?'),
                  content: Text(
                    'This account is scheduled for deletion. You can keep it before $deadline and restore your profile, echoes, and trust history.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Do not keep'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Keep account'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  _accountRecoveryDialogOpen = false;

  if (!authService.isLoggedIn) return;

  if (keepAccount == true) {
    unawaited(AppHaptics.criticalConfirm(key: 'account_recovery_keep'));
    final restored = await authService.restorePendingAccountDeletion();
    if (restored) {
      router.go('/feed');
      final snackContext = HyperSnackbar.navigatorKey.currentContext;
      if (snackContext != null && snackContext.mounted) {
        showInfoSnack(snackContext, 'Your account is active again.');
      }
    } else {
      final snackContext = HyperSnackbar.navigatorKey.currentContext;
      if (snackContext != null && snackContext.mounted) {
        showErrorSnack(
          snackContext,
          authService.error ?? 'Could not restore this account.',
        );
      }
    }
    return;
  }

  unawaited(AppHaptics.caution(key: 'account_recovery_dismiss'));
  await authService.signOut(enforceCooldown: false);
  router.go('/login');
}

String _formatRecoveryDeadline(DateTime deadline) {
  final local = deadline.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} at $hour:$minute';
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

  final location = _internalLocationForUri(uri);
  if (location != null) {
    _safeGo(router, location, auth: auth);
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

  final host = uri.host.toLowerCase();
  final isEchoProofLink =
      uri.scheme == 'echoproof' ||
      host == 'echoproof.online' ||
      host == 'www.echoproof.online' ||
      host == 'join.echoproof.online' ||
      host == 'www.join.echoproof.online';
  if (isEchoProofLink) {
    AppLogger.warn('deep link: unsupported link ignored $uri');
    _safeGo(router, '/feed?notice=unsupported-link', auth: auth);
  }
}

String? _internalLocationForUri(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (uri.scheme == 'echoproof') {
    if (uri.host == 'room' && (segments.isEmpty || segments.first == 'join')) {
      return _roomInviteLocation(uri);
    }
    if (uri.host == 'echo') {
      final id = segments.isNotEmpty
          ? segments.first
          : uri.queryParameters['id'];
      if (id != null && id.trim().isNotEmpty) {
        return _withOriginalQuery(
          '/feed/echo/${Uri.encodeComponent(id.trim())}',
          uri,
        );
      }
    }
    if (uri.host == 'user') {
      final username = segments.isNotEmpty
          ? segments.first
          : uri.queryParameters['username'];
      if (username != null && username.trim().isNotEmpty) {
        return _withOriginalQuery(
          '/profile/${Uri.encodeComponent(username.trim())}',
          uri,
        );
      }
    }
  }

  final host = uri.host.toLowerCase();
  final isMainHost =
      uri.scheme == 'https' &&
      (host == 'echoproof.online' || host == 'www.echoproof.online');
  final isJoinHost =
      uri.scheme == 'https' &&
      (host == 'join.echoproof.online' || host == 'www.join.echoproof.online');

  if (isJoinHost && (segments.isEmpty || segments.first == 'room')) {
    return _roomInviteLocation(uri);
  }

  if (isMainHost || uri.scheme.isEmpty) {
    if (segments.isNotEmpty && segments.first == 'room') {
      return _roomInviteLocation(uri);
    }
    if (segments.length >= 2 && (segments[0] == 'echo' || segments[0] == 'e')) {
      return _withOriginalQuery(
        '/feed/echo/${Uri.encodeComponent(segments[1])}',
        uri,
      );
    }
    if (segments.length >= 2 && (segments[0] == 'user' || segments[0] == 'u')) {
      return _withOriginalQuery(
        '/profile/${Uri.encodeComponent(segments[1])}',
        uri,
      );
    }
  }

  return null;
}

String _withOriginalQuery(String path, Uri uri) {
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

String _normalizedRouteLocation(String rawLocation) {
  final location = rawLocation.trim();
  if (location.isEmpty) return '/feed';

  try {
    final uri = Uri.parse(location);
    final internal = _internalLocationForUri(uri);
    if (internal != null) return internal;
  } catch (e) {
    AppLogger.warn('deep link: could not parse route $e');
  }

  if (!location.startsWith('/')) return '/feed';

  final uri = Uri.parse(location);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 2 && (segments[0] == 'echo' || segments[0] == 'e')) {
    return Uri(
      path: '/feed/echo/${segments[1]}',
      queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
    ).toString();
  }
  if (segments.length == 1 && segments.first == 'room') {
    return _roomInviteLocation(uri);
  }
  return location;
}

String _roomInviteLocation(Uri uri) {
  final fragmentParams = _safeFragmentParams(uri);
  final rawCode = uri.queryParameters['code'] ?? fragmentParams['code'] ?? '';
  final code = _normalizedRoomCode(rawCode);
  final key = (uri.queryParameters['key'] ?? fragmentParams['key'] ?? '')
      .trim();
  final query = <String, String>{};
  if (code != null) query['code'] = code;
  if (key.isNotEmpty) query['key'] = key;
  return Uri(
    path: '/rooms',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

Map<String, String> _safeFragmentParams(Uri uri) {
  if (uri.fragment.trim().isEmpty) return const <String, String>{};

  try {
    return Uri.splitQueryString(uri.fragment);
  } catch (e) {
    AppLogger.warn('deep link: invalid fragment ignored $e');
    return const <String, String>{};
  }
}

String? _normalizedRoomCode(String raw) {
  final code = raw.trim().toUpperCase();
  if (RegExp(r'^[A-Z2-9]{8}$').hasMatch(code)) return code;
  if (code.isNotEmpty) {
    AppLogger.warn('deep link: invalid room code ignored');
  }
  return null;
}

void _safeGo(GoRouter router, String location, {AuthService? auth}) {
  final normalized = _normalizedRouteLocation(location);
  if (auth != null && !auth.isLoggedIn) {
    _pendingDeepLinkLocation = normalized;
    router.go('/login?continue=1');
    return;
  }

  try {
    router.go(normalized);
  } on GoException catch (e) {
    AppLogger.warn('deep link: route failed for $normalized: $e');
    router.go('/feed?notice=unsupported-link');
  } catch (e) {
    AppLogger.warn('deep link: route failed for $normalized: $e');
    router.go('/feed?notice=unsupported-link');
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
  final isHttpsAuth =
      uri.scheme == 'https' &&
      (uri.host == 'echoproof.online' || uri.host == 'www.echoproof.online') &&
      ((uri.pathSegments.length == 1 &&
              uri.pathSegments[0] == 'auth-callback') ||
          (uri.pathSegments.length >= 2 &&
              uri.pathSegments[0] == 'auth' &&
              uri.pathSegments[1] == 'callback'));
  final hasAuthPayload =
      uri.queryParameters.containsKey('code') ||
      uri.queryParameters.containsKey('token_hash') ||
      uri.queryParameters.containsKey('error_description') ||
      uri.fragment.contains('access_token') ||
      uri.fragment.contains('error_description');

  return (isCustomAuth || isHttpsAuth) && hasAuthPayload;
}

bool _quickActionsAllowed(AuthService auth) {
  return auth.isLoggedIn && auth.hasUsername && !auth.needsAgeGender;
}

class _AppLifecycleObserver extends WidgetsBindingObserver {
  _AppLifecycleObserver(
    this._sub,
    this._auth,
    this._devices,
    this._updates,
    this._router,
  );
  final SubscriptionService _sub;
  final AuthService _auth;
  final AccountDeviceService _devices;
  final AppUpdateService _updates;
  final GoRouter _router;
  DateTime? _backgroundedAt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      final backgroundedFor = backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(backgroundedAt);
      AppLogger.info('subscription: app resumed, checking checkout state');
      unawaited(_sub.recoverCheckoutAfterResume());
      unawaited(_verifyAccountAfterResume());
      if (backgroundedFor >= const Duration(seconds: 8)) {
        unawaited(
          _updates.checkForRequiredUpdate(
            reason: AppUpdateCheckReason.resume,
            force: backgroundedFor >= const Duration(seconds: 30),
          ),
        );
      }
    }
  }

  Future<void> _verifyAccountAfterResume() async {
    if (!_auth.isLoggedIn) return;

    await _auth.checkUsername();
    if (!_auth.isLoggedIn) {
      _router.go('/login');
      return;
    }

    await _devices.startRealtime(_auth, _router);
    unawaited(_maybeShowAccountRecoveryDialog(_auth, _router));
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
