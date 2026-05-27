import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/services/auth_service.dart';
import '../utils/logger.dart';
import '../utils/snack.dart';
import 'device_service.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';

class AccountDeviceRecord {
  const AccountDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.active,
    this.lastSeenAt,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final bool active;
  final DateTime? lastSeenAt;

  factory AccountDeviceRecord.fromMap(Map<String, dynamic> map) {
    return AccountDeviceRecord(
      deviceId: map['device_id'] as String? ?? '',
      deviceName: map['device_name'] as String? ?? 'Unknown device',
      platform: map['platform'] as String? ?? 'unknown',
      active: map['active'] as bool? ?? false,
      lastSeenAt: DateTime.tryParse(map['last_seen_at'] as String? ?? ''),
    );
  }
}

class AccountDeviceConflict implements Exception {
  const AccountDeviceConflict(this.currentDevice, this.message);

  final AccountDeviceRecord currentDevice;
  final String message;
}

class AccountDeviceService extends ChangeNotifier {
  AccountDeviceService();

  final _client = Supabase.instance.client;
  final _deviceService = DeviceService(const FlutterSecureStorage());

  RealtimeChannel? _channel;
  Timer? _heartbeatTimer;
  AccountDeviceRecord? _currentDevice;
  AccountDeviceConflict? _pendingConflict;
  List<AccountDeviceRecord> _devices = const [];
  bool _registering = false;
  bool _handlingInvalidation = false;

  AccountDeviceRecord? get currentDevice => _currentDevice;
  AccountDeviceConflict? get pendingConflict => _pendingConflict;
  List<AccountDeviceRecord> get devices => List.unmodifiable(_devices);
  bool get registering => _registering;

  Future<AccountDeviceRecord> register({bool force = false}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Sign in again.');

    _registering = true;
    notifyListeners();
    try {
      final deviceId = await _deviceService.getDeviceId();
      final response = await _client.functions.invoke(
        'register-account-device',
        body: {
          'device_id': deviceId,
          'device_name': _deviceName,
          'platform': _deviceService.platform,
          'force': force,
        },
      );
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['error'] == 'device_conflict') {
        final current =
            Map<String, dynamic>.from(data['current_device'] as Map);
        _pendingConflict = AccountDeviceConflict(
          AccountDeviceRecord.fromMap(current),
          data['message'] as String? ??
              'Your account is active on another device.',
        );
        notifyListeners();
        throw _pendingConflict!;
      }
      if (data['error'] != null) {
        throw Exception(data['message'] ?? data['error']);
      }
      final record = AccountDeviceRecord.fromMap(
        Map<String, dynamic>.from(data['device'] as Map),
      );
      _currentDevice = record;
      _pendingConflict = null;
      await loadDevices();
      return record;
    } finally {
      _registering = false;
      notifyListeners();
    }
  }

  Future<void> loadDevices() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _devices = const [];
      notifyListeners();
      return;
    }
    final rows = await _client
        .from('account_devices')
        .select('device_id, device_name, platform, active, last_seen_at')
        .eq('user_id', userId)
        .eq('active', true)
        .order('last_seen_at', ascending: false);
    _devices = (rows as List)
        .map((row) => AccountDeviceRecord.fromMap(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList();
    notifyListeners();
  }

  Future<AccountDeviceRecord> continueOnThisDevice() {
    return register(force: true);
  }

  Future<bool> heartbeat() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return true;
    try {
      final deviceId = await _deviceService.getDeviceId();
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await _client
          .from('account_devices')
          .update({
            'last_seen_at': now,
            'updated_at': now,
          })
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .eq('active', true)
          .select('device_id, device_name, platform, active, last_seen_at');
      final list = rows as List;
      if (list.isEmpty) {
        AppLogger.warn(
          'device-session: heartbeat found no active row for this device',
        );
        return false;
      }
      _currentDevice = AccountDeviceRecord.fromMap(
        Map<String, dynamic>.from(list.first as Map),
      );
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.warn('device-session: heartbeat skipped $e');
      return true;
    }
  }

  void clearPendingConflict() {
    _pendingConflict = null;
    notifyListeners();
  }

  Future<void> startRealtime(AuthService authService, GoRouter router) async {
    await stopRealtime();
    final deviceId = await _deviceService.getDeviceId();
    final active = await heartbeat();
    if (!active) {
      await _handleInvalidatedDevice(
        authService,
        router,
        'This device is no longer the active session. Logging out here.',
      );
      return;
    }
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_heartbeatAndEnforce(authService, router)),
    );
    _channel = _client
        .channel('account_device_$deviceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'account_devices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'device_id',
            value: deviceId,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            final active = row['active'] as bool? ?? true;
            if (active) return;
            AppLogger.warn('device-session: current device was replaced');
            await _handleInvalidatedDevice(
              authService,
              router,
              'Your account was opened on another device. Logging out here.',
            );
          },
        )
        .subscribe();
  }

  Future<void> _heartbeatAndEnforce(
    AuthService authService,
    GoRouter router,
  ) async {
    final active = await heartbeat();
    if (!active) {
      await _handleInvalidatedDevice(
        authService,
        router,
        'This device is no longer the active session. Logging out here.',
      );
    }
  }

  Future<void> _handleInvalidatedDevice(
    AuthService authService,
    GoRouter router,
    String message,
  ) async {
    if (_handlingInvalidation) return;
    _handlingInvalidation = true;
    try {
      final context = HyperSnackbar.navigatorKey.currentContext;
      if (context != null) {
        showWarningSnack(context, message);
      }
      await stopRealtime();
      await authService.signOut(enforceCooldown: false);
      router.go('/login');
    } finally {
      _handlingInvalidation = false;
    }
  }

  Future<void> stopRealtime() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  String get _deviceName {
    final host = Platform.localHostname.trim();
    if (host.isEmpty || host == 'localhost') {
      return Platform.isAndroid
          ? 'Android phone'
          : Platform.isIOS
              ? 'iPhone'
              : '${Platform.operatingSystem} device';
    }
    return host;
  }
}
