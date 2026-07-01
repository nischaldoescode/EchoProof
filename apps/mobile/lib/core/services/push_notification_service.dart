// push notification service
// @params none

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'connectivity_service.dart';
import '../utils/logger.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.info('fcm: background message ${message.messageId}');
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifs = FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<String>? _tokenRefreshSub;
  Timer? _tokenRetryTimer;
  String? _pendingTokenRetry;
  int _tokenRetryAttempt = 0;
  bool _initialized = false;

  static const _channelId = 'echoproof_default';
  static const _channelName = 'Echoproof';
  static const _channelDesc =
      'Echo verification, trust updates, and community activity';

  Future<void> initialize() async {
    if (_initialized) {
      await _saveToken();
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    AppLogger.info('fcm: permission ${settings.authorizationStatus.name}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      AppLogger.warn('fcm: permission denied — push disabled');
      return;
    }

    // v18+ api uses named 'settings' parameter
    await _localNotifs.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      ),
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleMessageTap(initial);

    await _saveToken();
    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_onTokenRefresh);
    _initialized = true;
  }

  Future<void> _saveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) return;
      AppLogger.info('fcm: token obtained');
      await _persistToken(token);
    } catch (e) {
      if (AppLogger.isTransientNetworkError(e, 'fcm: get token failed')) {
        AppLogger.warn('fcm: token retry scheduled after transient network');
        _scheduleTokenRetry();
        return;
      }
      AppLogger.error('fcm: get token failed', e);
    }
  }

  Future<void> _persistToken(String token) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await client.from('device_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.android
            ? 'android'
            : 'ios',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,token');
      AppLogger.info('fcm: token saved');
      _pendingTokenRetry = null;
      _tokenRetryAttempt = 0;
    } catch (e) {
      if (AppLogger.isTransientNetworkError(e, 'fcm: save token failed')) {
        AppLogger.warn('fcm: save token retry scheduled transient network');
        _scheduleTokenRetry(token: token);
        return;
      }
      AppLogger.error('fcm: save token failed', e);
    }
  }

  void _scheduleTokenRetry({String? token}) {
    _pendingTokenRetry = token ?? _pendingTokenRetry;
    if (_tokenRetryTimer?.isActive ?? false) return;
    final attempt = _tokenRetryAttempt.clamp(0, 5);
    final baseSeconds = ConnectivityService.instance.isOnline ? 8 : 24;
    final delay = Duration(seconds: baseSeconds * (attempt + 1));

    // token registration is idempotent because the db upsert uses user+token.
    // retrying quietly avoids losing push capability when android turns the
    // screen off, dns changes, or supabase closes a background socket mid-write.
    _tokenRetryTimer = Timer(delay, () {
      _tokenRetryAttempt = (_tokenRetryAttempt + 1).clamp(0, 5);
      final pending = _pendingTokenRetry;
      if (pending == null) {
        unawaited(_saveToken());
      } else {
        unawaited(_persistToken(pending));
      }
    });
  }

  void _onTokenRefresh(String token) {
    AppLogger.info('fcm: token refreshed');
    _persistToken(token);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.info('fcm: foreground ${message.messageId}');
    final notif = message.notification;
    if (notif == null) return;

    // v18+ api uses named parameters id, title, body, notificationdetails
    await _localNotifs.show(
      id: message.hashCode,
      title: notif.title,
      body: notif.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF4CAF6E),
        ),
      ),
      payload: message.data['route'] as String?,
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    AppLogger.info('fcm: tapped ${message.data}');
    // navigation handled in main.dart via firebasemessaging.onmessageopenedapp
  }

  void _onNotificationTapped(NotificationResponse response) {
    AppLogger.info('fcm: local notif tapped ${response.payload}');
    final route = response.payload;
    final context = HyperSnackbar.navigatorKey.currentContext;
    if (context == null || route == null || route.isEmpty) return;
    GoRouter.of(context).push(route);
  }

  Future<void> removeToken() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;

    try {
      final token = await _messaging.getToken();
      if (token != null && userId != null) {
        await client
            .from('device_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', token);
      }
      if (token != null) {
        await _messaging.deleteToken();
      }
      await _foregroundSub?.cancel();
      await _openedSub?.cancel();
      await _tokenRefreshSub?.cancel();
      _tokenRetryTimer?.cancel();
      _foregroundSub = null;
      _openedSub = null;
      _tokenRefreshSub = null;
      _pendingTokenRetry = null;
      _tokenRetryAttempt = 0;
      _initialized = false;
    } catch (e) {
      AppLogger.error('fcm: remove token failed', e);
    }
  }
}
