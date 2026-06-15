// account device service
// @params none

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/services/auth_service.dart';
import '../utils/logger.dart';
import '../utils/app_haptics.dart';
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
  const AccountDeviceConflict(
    this.currentDevice,
    this.message, {
    this.kind = 'different_device',
    this.sameNamedDevice = false,
    this.lastSeenAgeSeconds,
  });

  final AccountDeviceRecord currentDevice;
  final String message;
  final String kind;
  final bool sameNamedDevice;
  final int? lastSeenAgeSeconds;
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
  int _heartbeatMisses = 0;

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
      final deviceName = await _deviceName();
      final response = await _client.functions.invoke(
        'register-account-device',
        body: {
          'device_id': deviceId,
          'device_name': deviceName,
          'platform': _deviceService.platform,
          'force': force,
        },
      );
      final data = _mapData(response.data);
      if (data['error'] == 'device_conflict') {
        await _throwDeviceConflict(data);
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
    } on FunctionException catch (e) {
      final data = _tryMapData(e.details);
      if (e.status == 409 && data?['error'] == 'device_conflict') {
        await _throwDeviceConflict(data!);
      }
      throw Exception(
        data?['message'] ??
            data?['error'] ??
            e.reasonPhrase ??
            'Could not register this device.',
      );
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
        .map(
          (row) => AccountDeviceRecord.fromMap(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
    notifyListeners();
  }

  Future<AccountDeviceRecord> continueOnThisDevice() {
    return register(force: true);
  }

  Future<AccountDeviceRecord> secureThisDevice() {
    return register(force: true);
  }

  Future<Never> _throwDeviceConflict(Map<String, dynamic> data) async {
    final current = Map<String, dynamic>.from(data['current_device'] as Map);
    _pendingConflict = AccountDeviceConflict(
      AccountDeviceRecord.fromMap(current),
      data['message'] as String? ?? 'Your account is active on another device.',
      kind: data['conflict_kind'] as String? ?? 'different_device',
      sameNamedDevice: data['same_named_device'] as bool? ?? false,
      lastSeenAgeSeconds: (data['last_seen_age_seconds'] as num?)?.toInt(),
    );
    await loadDevices().catchError((_) {});
    notifyListeners();
    throw _pendingConflict!;
  }

  Future<bool> heartbeat() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return true;
    try {
      final deviceId = await _deviceService.getDeviceId();
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await _client
          .from('account_devices')
          .update({'last_seen_at': now, 'updated_at': now})
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .eq('active', true)
          .select('device_id, device_name, platform, active, last_seen_at');
      final list = rows as List;
      if (list.isEmpty) {
        AppLogger.warn(
          'device-session: heartbeat found no active row for this device',
        );
        final confirmedInactive = await _currentDeviceIsInactive(
          userId,
          deviceId,
        );
        if (!confirmedInactive) {
          _heartbeatMisses = 0;
          return true;
        }

        _heartbeatMisses += 1;
        if (_heartbeatMisses < 2) {
          AppLogger.warn(
            'device-session: heartbeat miss grace $_heartbeatMisses/2',
          );
          return true;
        }
        return false;
      }
      _heartbeatMisses = 0;
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
            await Future<void>.delayed(const Duration(milliseconds: 900));
            if (!authService.isLoggedIn) return;
            final stillInactive = await _currentDeviceIsInactive(
              authService.currentUser?.id,
              deviceId,
            );
            if (!stillInactive) return;
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
        unawaited(AppHaptics.caution(key: 'device_invalidated'));
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
    _heartbeatMisses = 0;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  Future<bool> _currentDeviceIsInactive(String? userId, String deviceId) async {
    if (userId == null) return false;
    try {
      final row = await _client
          .from('account_devices')
          .select('active, replaced_at, last_seen_at')
          .eq('user_id', userId)
          .eq('device_id', deviceId)
          .maybeSingle();
      if (row == null) {
        AppLogger.warn(
          'device-session: current device row missing during confirmation',
        );
        return false;
      }
      return (row['active'] as bool?) == false;
    } catch (e) {
      AppLogger.warn('device-session: inactive confirmation skipped $e');
      return false;
    }
  }

  Future<String> _deviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final manufacturer = _prettyPart(info.manufacturer);
        final model = _prettyPart(info.model);
        if (model.isNotEmpty && manufacturer.isNotEmpty) {
          final lowerModel = model.toLowerCase();
          final lowerMaker = manufacturer.toLowerCase();
          if (lowerModel.contains(lowerMaker)) return model;
          return '$manufacturer $model';
        }
        if (model.isNotEmpty) return model;
        final device = _prettyPart(info.device);
        if (device.isNotEmpty) return device;
      }

      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final name = _prettyPart(info.name);
        if (name.isNotEmpty && name.toLowerCase() != 'iphone') return name;
        final model = _prettyPart(info.utsname.machine);
        if (model.isNotEmpty) return model;
        return 'iPhone';
      }
    } catch (e) {
      AppLogger.warn('device-session: device name lookup failed $e');
    }

    final host = Platform.localHostname.trim();
    if (host.isNotEmpty && host != 'localhost') return host;
    return Platform.isAndroid
        ? 'Android phone'
        : Platform.isIOS
        ? 'iPhone'
        : '${Platform.operatingSystem} device';
  }

  String _prettyPart(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned.toLowerCase() == 'unknown') return '';
    return cleaned
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  Map<String, dynamic> _mapData(Object? value) {
    final map = _tryMapData(value);
    if (map != null) return map;
    throw Exception('Invalid device registration response.');
  }

  Map<String, dynamic>? _tryMapData(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }
}
