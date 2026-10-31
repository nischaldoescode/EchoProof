// widget tests for app motion surfaces
// keeps swipe cancellation and compact onboarding layout from regressing

import 'dart:io';

import 'package:echoproof/app/theme/app_theme.dart';
import 'package:echoproof/features/onboarding/presentation/widgets/onboarding_story_frame.dart';
import 'package:echoproof/core/security/device_security.dart';
import 'package:echoproof/core/security/device_security_gate.dart';
import 'package:echoproof/shared/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('root swipe wrapper settles cancelled drags without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const SwipeNavigationWrapper(
          currentLocation: '/discover',
          child: Scaffold(body: Center(child: Text('root screen'))),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('root screen')),
    );
    await gesture.moveBy(const Offset(84, 0));
    await tester.pump();
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    final maxHorizontalOffset = transforms.fold<double>(0, (maxOffset, t) {
      final x = t.transform.storage[12].abs();
      return x > maxOffset ? x : maxOffset;
    });
    expect(maxHorizontalOffset, lessThanOrEqualTo(20));

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 220));

    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding story frame fits compact split-screen height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OnboardingStoryFrame(
          currentStep: 1,
          totalSteps: 7,
          title: 'story title',
          body: 'short body that can wrap on compact screens',
          sceneIcon: Icons.shield_outlined,
          sceneLabel: 'compact scene label',
          footer: ElevatedButton(onPressed: () {}, child: const Text('next')),
          children: const [
            Text('content row'),
            SizedBox(height: 12),
            Text('another compact row'),
          ],
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 450));

    expect(tester.takeException(), isNull);
    expect(find.text('story title'), findsOneWidget);
    expect(find.text('next'), findsOneWidget);
  });

  test('discover defaults to india and keeps manual country scope', () {
    final source = File(
      'lib/features/echo/presentation/screens/discover_screen.dart',
    ).readAsStringSync();

    expect(source, contains("static const String _defaultCountryCode = 'IN'"));
    expect(source, contains('static bool _hasStoredCountryChoice = false'));
    expect(source, contains('? _lastSelectedCountry'));
    expect(source, contains(': _defaultCountryCode'));
    expect(source, contains('_hasStoredCountryChoice = true'));
    expect(source, contains('_lastSelectedCountry = code'));
    expect(source, isNot(contains('IpHunter')));
    expect(source, isNot(contains('_detectCountryAndLoad')));
    expect(source, isNot(contains('_entranceController')));
  });

  test('signal drift keeps harder play from tunneling through reflectors', () {
    final source = File(
      'lib/features/echo/presentation/screens/echo_signal_game_screen.dart',
    ).readAsStringSync();
    final physicsSource = File(
      'lib/features/echo/presentation/services/signal_drift_physics.dart',
    ).readAsStringSync();

    expect(source, contains('radius * 0.035'));
    expect(source, contains('final stepCap = _liteMode ? 200 : 320'));
    expect(source, contains('_reflectorCollisionPadding(radius)'));
    expect(physicsSource, contains('radius + (liteMode ? 16 : 18)'));
    expect(source, contains('inMilliseconds < 64'));
    expect(source, contains('inflate(radius + 6)'));
    expect(
      source,
      contains('_sweptCircleRectHit(previous, signal, rect, radius)'),
    );
    expect(source, contains('_movingAwayFromRect'));
    expect(source, contains('_escapeReflectorBand'));
    expect(source, contains('SignalDriftPhysics.escapeReflectorBand'));
    expect(source, contains('SignalDriftPhysics.forgeCircleOverlapsRect'));
    expect(physicsSource, contains("package:forge2d/forge2d.dart"));
    expect(physicsSource, contains('collidePolygonAndCircle'));
    expect(physicsSource, contains('reflectorSize.width / 2 + 26'));
    expect(source, contains('_applyNaturalPaceVariation'));
    expect(source, contains('_settleReflectorCenter'));
    expect(source, contains('lastExitVelocity'));
    expect(source, contains('_velocitySimilarity(previous, velocity) > 0.94'));
    expect(
      source,
      contains('_rotateVelocity(velocity, horizontalSign * radians)'),
    );
    expect(source, contains('speedBeforeHorizontalCap'));
    expect(source, contains('preservedVertical'));
    expect(source, contains('_stabilizePlayableExit'));
    expect(source, contains('_SignalExitSource.wall'));
    expect(source, contains('_SignalExitSource.ceiling'));
    expect(source, contains('_SignalExitSource.paddle'));
    expect(source, contains('_laneSimilarity(previous, adjusted) > 0.975'));
    expect(source, contains('_withHorizontalFloor'));
    expect(source, contains('baseMaxSpeed = _liteMode ? 930.0 : 1210.0'));
    expect(source, contains('baseUnlock: 4'));
    expect(source, contains('baseUnlock: 54'));
    expect(source, contains('baseUnlock: 72'));
    expect(source, contains('id: 6'));
    expect(physicsSource, contains('score < 10'));
    expect(source, contains('width.clamp(320.0, 760.0).toDouble() * 0.235'));
  });

  test('screenshots stay scoped to secure rooms and lockdown only', () {
    final secureScreen = File(
      'lib/core/security/secure_screen.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/echoproof/app/MainActivity.kt',
    ).readAsStringSync();
    final router = File(
      'lib/app/router.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final gate = File(
      'lib/core/security/device_security_gate.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final profile = File(
      'lib/features/profile/presentation/screens/profile_screen.dart',
    ).readAsStringSync();
    final imageViewer = File(
      'lib/shared/widgets/image_viewer.dart',
    ).readAsStringSync();

    expect(secureScreen, contains('clearFlags'));
    expect(secureScreen, contains('if (_activeLocks > 0) return'));
    expect(mainActivity, contains('clearSecureWindow'));
    expect(
      mainActivity,
      isNot(
        contains(
          'override fun onCreate(savedInstanceState: Bundle?) {\n        // keep screenshots',
        ),
      ),
    );
    expect(main, isNot(contains('DeviceSecurity.enforceSecureWindow()')));
    expect(gate, contains('return widget.child'));
    expect(router, contains('SecureScreen(\n            child: RoomsScreen'));
    expect(
      router,
      contains('SecureScreen(\n            child: SecureRoomChatScreen'),
    );
    expect(router, contains('profile check waiting for network'));
    expect(profile, isNot(contains('SecureScreen(child: _buildBody())')));
    expect(imageViewer, isNot(contains('FlutterWindowManagerPlus')));
  });

  testWidgets('security screen does not call play install failures rooted', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecurityLockdownScreen(
          report: DeviceSecurityReport(
            compromised: true,
            reasons: ['installer_missing'],
          ),
        ),
      ),
    );

    expect(find.text('Install from Google Play'), findsOneWidget);
    expect(find.textContaining('not installed from a trusted store'), findsOne);
    expect(find.textContaining('rooted, jailbroken'), findsNothing);
  });

  test('security hardening keeps auth logs and rpc grants scoped', () {
    final authService = File(
      'lib/features/auth/presentation/services/auth_service.dart',
    ).readAsStringSync();
    final deviceSecurity = File(
      'lib/core/security/device_security.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/echoproof/app/MainActivity.kt',
    ).readAsStringSync();
    final grantMigration = File(
      '../../supabase/migrations/20260628120000_security_definer_rpc_grants.sql',
    ).readAsStringSync();

    expect(authService, contains('_trustedEmailDomains'));
    expect(authService, contains('_client.auth.currentSession == null'));
    expect(authService, contains('_googlePlatformFailureLabel'));
    expect(
      authService,
      isNot(contains('Google platform sign in failed code=')),
    );
    expect(authService, isNot(contains(r'Google sign in error: $e')));
    expect(deviceSecurity, contains('modified_mount_state'));
    expect(deviceSecurity, contains('su_binary_available'));
    expect(deviceSecurity, contains('hasInstallIntegrityIssue'));
    expect(deviceSecurity, contains('hasDeviceIntegrityIssue'));
    expect(deviceSecurity, contains('installer_missing'));
    expect(deviceSecurity, contains('androidInstallerPackageName'));
    expect(deviceSecurity, contains('server-verified play integrity verdict'));
    expect(mainActivity, contains('"installerPackageName"'));
    expect(mainActivity, contains('mountIndicators()'));
<<<<<<< HEAD
=======
    expect(mainActivity, contains('generic overlay mounted near /system'));
    expect(mainActivity, isNot(contains('indicators += "system_overlay"')));
>>>>>>> master
    expect(mainActivity, contains('suProbe()'));
    expect(mainActivity, contains('tracerPid()'));
    expect(grantMigration, contains('service_only_rpc'));
    expect(
      grantMigration,
      contains(
        'public.get_personalized_feed_cursor(uuid,integer,numeric,timestamptz,uuid,text)',
      ),
    );
    expect(
      grantMigration,
      contains('revoke all on function %s from public, anon, authenticated'),
    );
  });

  test('error monitoring stays private, readable, and background only', () {
    final monitor = File(
      'lib/core/services/error_monitoring_service.dart',
    ).readAsStringSync();
    final logger = File('lib/core/utils/logger.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
<<<<<<< HEAD
=======
    final runtimeConfig = File(
      'lib/core/config/runtime_config.dart',
    ).readAsStringSync();
>>>>>>> master
    final analyticsService = File(
      'lib/core/services/app_analytics_service.dart',
    ).readAsStringSync();
    final appUpdateService = File(
      'lib/core/services/app_update_service.dart',
    ).readAsStringSync();
    final authService = File(
      'lib/features/auth/presentation/services/auth_service.dart',
    ).readAsStringSync();
    final networkLogger = File(
      'lib/core/network/interceptors/logging_interceptor.dart',
    ).readAsStringSync();
    final pushService = File(
      'lib/core/services/push_notification_service.dart',
    ).readAsStringSync();
    final privacy = File(
      '../echoproof-web/app/privacy/page.tsx',
    ).readAsStringSync();
    final terms = File(
      '../echoproof-web/app/terms/page.tsx',
    ).readAsStringSync();

    expect(monitor, contains('SENTRY_DSN'));
    expect(monitor, contains('SENTRY_PROFILES_SAMPLE_RATE'));
    expect(monitor, contains('SENTRY_METRICS_SAMPLE_RATE'));
    expect(monitor, contains('sendDefaultPii = false'));
    expect(monitor, contains('attachScreenshot = false'));
    expect(monitor, contains('attachViewHierarchy = false'));
    expect(monitor, contains('enableUserInteractionTracing = false'));
    expect(monitor, contains('enableMetrics = _metricsEnabled'));
    expect(monitor, contains('tracePropagationTargets'));
    expect(monitor, contains('SentryNavigatorObserver'));
    expect(monitor, contains('captureAnalyticsEvent'));
    expect(monitor, contains('captureScreenView'));
    expect(monitor, contains('Sentry.metrics.count'));
    expect(monitor, contains('sha256.convert'));
    expect(monitor, contains('captureFailedRequests = false'));
    expect(monitor, contains('anrEnabled = true'));
    expect(monitor, contains('maxRequestBodySize = MaxRequestBodySize.never'));
    expect(monitor, contains('beforeSend = _beforeSend'));
<<<<<<< HEAD
=======
    expect(monitor, contains("setContexts('device_security'"));
    expect(monitor, contains('mount_indicators'));
    expect(monitor, contains('installer_class'));
    expect(monitor, contains('signing_certificate_count'));
    expect(monitor, contains('raw native signal payloads'));
>>>>>>> master
    expect(monitor, contains('_isTransientNetworkEvent'));
    expect(monitor, contains('_sanitizeText'));
    expect(monitor, contains('access_token'));
    expect(monitor, contains('[id]'));
    expect(monitor, contains('[email]'));
    expect(monitor, isNot(contains('SentryWidget')));

    expect(logger, contains('ErrorMonitoringService.captureError'));
    expect(logger, contains('isTransientNetworkError'));
    expect(logger, contains('transient network skipped'));
    expect(main, contains('ErrorMonitoringService.initialize'));
    expect(main, contains('appRunner: _bootstrap'));
<<<<<<< HEAD
=======
    expect(main, contains('BootstrapFailureApp'));
    expect(main, contains("'app bootstrap failed'"));
    expect(main, contains('RuntimeConfig.supabasePublishableKey'));
    expect(runtimeConfig, contains('SUPABASE_PUBLISHABLE_KEY'));
    expect(runtimeConfig, contains('SUPABASE_ANON_KEY'));
>>>>>>> master
    expect(main, contains('AppAnalyticsService.instance.attachRouter'));
    expect(
      analyticsService,
      contains('ErrorMonitoringService.captureAnalyticsEvent'),
    );
    expect(
      analyticsService,
      contains('ErrorMonitoringService.captureScreenView'),
    );
    expect(analyticsService, contains('ErrorMonitoringService.setUser'));
    expect(appUpdateService, contains('_shouldSkipPlayUpdateForInstallSource'));
    expect(appUpdateService, contains('skipped non-play install'));
    expect(networkLogger, contains('network request failed'));
    expect(networkLogger, isNot(contains(', err')));
    expect(authService, contains('build not verified'));
    expect(authService, contains('provider token'));
<<<<<<< HEAD
=======
    expect(authService, contains('supabase configuration'));
>>>>>>> master
    expect(authService, contains('profile check skipped transient network'));
    expect(authService, contains('_restoreProfileStateFromLocalCache'));
    expect(authService, isNot(contains('build_not_verified')));
    expect(authService, isNot(contains('provider_token')));
    expect(authService, isNot(contains('platform_rejected')));
    expect(pushService, contains('_scheduleTokenRetry'));
    expect(
      pushService,
      contains('save token retry scheduled transient network'),
    );

    expect(privacy, contains('We do not sell your personal data'));
    expect(privacy, contains('age or date of birth'));
    expect(privacy, contains('Diagnostics and crash reports'));
    expect(terms, contains('We do not sell your personal data'));
    expect(terms, contains('Security and diagnostics'));
  });
<<<<<<< HEAD
=======

  test(
    'identity verification discloses didit ownership and scoped privacy link',
    () {
      final verification = File(
        'lib/features/auth/presentation/screens/identity_verification_screen.dart',
      ).readAsStringSync();

      expect(verification, contains("https://didit.me/terms/privacy-policy/"));
      expect(
        verification,
        contains('Identity verification is provided by Didit'),
      );
      expect(
        verification,
        contains('documents, selfies, and biometric processing'),
      );
      expect(verification, contains('verification outcome'));
      expect(verification, contains('abuse-prevention records'));
      expect(verification, contains(r"Please read Didit\'s privacy policy"));
      expect(verification, contains('showOpenLinkSheet'));
      expect(verification, contains('enabled: !_isLoading'));
      expect(verification, contains('loggingEnabled: kDebugMode'));
    },
  );
>>>>>>> master
}
