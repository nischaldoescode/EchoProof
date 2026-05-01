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
<<<<<<< HEAD
import 'core/utils/logger.dart';
import 'features/subscription/presentation/services/subscription_service.dart';
import '../../core/services/ad_service.dart';
=======
import 'features/subscription/presentation/services/subscription_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_portal/flutter_portal.dart';
import 'core/services/connectivity_service.dart';
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)

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
  );

  AppLogger.info('main: supabase initialized');
  await ConnectivityService.instance.initialize();

  final authService = AuthService();
  final onboardingService = OnboardingService();
  final echoFeedService = EchoFeedService();
  final createEchoService = CreateEchoService();
  final notificationService = NotificationService();
<<<<<<< HEAD
  final adService = AdService();
  final subscriptionService = SubscriptionService();
=======
  final subscriptionService = SubscriptionService();
  final adService = AdService();

  await authService.checkUsername();
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)

  final router = createRouter(
    authService: authService,
    onboardingService: onboardingService,
    subscriptionService: subscriptionService,
  );

  // handle notification tap — deep link to echo detail
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final route = message.data['route'] as String?;
    if (route != null && route.isNotEmpty) {
      router.push(route);
    }
  });

  // handle notification tap from terminated state
  FirebaseMessaging.instance.getInitialMessage().then((message) {
    if (message == null) return;
    final route = message.data['route'] as String?;
    if (route != null && route.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        router.push(route);
      });
    }
  });
  runApp(
<<<<<<< HEAD
    MultiProvider(
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
  );
}
=======
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

class _SecurityWarningApp extends StatelessWidget {
  const _SecurityWarningApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
