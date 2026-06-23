import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:go_router/go_router.dart';

/// records product events without sending user-generated text or identifiers.
class AppAnalyticsService {
  AppAnalyticsService._();

  static final AppAnalyticsService instance = AppAnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  GoRouter? _router;
  String? _lastScreen;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _analytics.setAnalyticsCollectionEnabled(true);
    await _analytics.logAppOpen();
  }

  void attachRouter(GoRouter router) {
    if (identical(_router, router)) return;
    _router = router;
    router.routeInformationProvider.addListener(() {
      final uri = router.routeInformationProvider.value.uri;
      unawaited(logScreen(uri));
    });
    unawaited(logScreen(router.routeInformationProvider.value.uri));
  }

  Future<void> setAuthenticatedUser({
    required String? userId,
    bool? isPro,
  }) async {
    await _run(() async {
      await _analytics.setUserId(id: userId);
      if (isPro != null) {
        await _analytics.setUserProperty(
          name: 'subscription_tier',
          value: isPro ? 'pro' : 'free',
        );
      }
    });
  }

  Future<void> logLogin({required String method}) {
    return _run(() => _analytics.logLogin(loginMethod: method));
  }

  Future<void> logSignUp({required String method}) {
    return _run(() => _analytics.logSignUp(signUpMethod: method));
  }

  Future<void> logScreen(Uri uri) async {
    final screen = _screenName(uri);
    if (screen == _lastScreen) return;
    _lastScreen = screen;
    await _run(
      () => _analytics.logScreenView(screenName: screen, screenClass: screen),
    );
  }

  Future<void> logEvent(
    String name, {
    Map<String, Object?> parameters = const {},
  }) {
    return _run(
      () => _analytics.logEvent(
        name: name,
        parameters: _safeParameters(parameters),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // analytics is observational and must never interrupt a user action.
    }
  }

  Map<String, Object> _safeParameters(Map<String, Object?> source) {
    final output = <String, Object>{};
    for (final entry in source.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(key)) continue;
      if (value is String) {
        output[key] = value.length > 100 ? value.substring(0, 100) : value;
      } else if (value is bool) {
        output[key] = value ? 1 : 0;
      } else if (value is int) {
        output[key] = value;
      } else if (value is double) {
        output[key] = value;
      }
    }
    return output;
  }

  String _screenName(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.isEmpty || uri.path == '/') return 'dashboard';
    if (segments.first == 'feed' && segments.length > 1) {
      return 'echo_detail';
    }
    if (segments.first == 'profile' && segments.length > 1) {
      return 'profile';
    }
    if (segments.first == 'rooms' && segments.length > 1) {
      return 'secure_room';
    }
    if (segments.first == 'echo' && segments.length > 1) return 'echo_detail';
    return segments.first.replaceAll('-', '_');
  }
}
