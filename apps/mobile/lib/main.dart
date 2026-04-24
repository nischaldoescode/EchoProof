// echoproof app entry point
// initializes supabase, hive, and all services before runApp
// uses provider package for dependency injection — no riverpod

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'app/router.dart';
import 'features/auth/presentation/services/auth_service.dart';
import 'features/onboarding/presentation/services/onboarding_service.dart';
import 'features/echo/presentation/services/echo_feed_service.dart';
import 'features/echo/presentation/services/create_echo_service.dart';
import 'features/notifications/presentation/services/notification_service.dart';
import 'core/utils/logger.dart';
import 'features/subscription/presentation/services/subscription_service.dart';
import '../../core/services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // supabase url and anon key are injected at build time via --dart-define
  // never hardcode these values here
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  AppLogger.info('main: supabase initialized');

  final authService = AuthService();
  final onboardingService = OnboardingService();
  final echoFeedService = EchoFeedService();
  final createEchoService = CreateEchoService();
  final notificationService = NotificationService();
  final adService = AdService();
  final subscriptionService = SubscriptionService();

  final router = createRouter(
    authService: authService,
    onboardingService: onboardingService,
    subscriptionService: subscriptionService,
  );

  runApp(
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
