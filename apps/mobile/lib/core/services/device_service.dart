// device service
// generates a stable device fingerprint stored in users_private
// used as a secondary fraud signal — not for tracking

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';

const _kDeviceId = 'device_fingerprint';

class DeviceService {
  DeviceService(this._storage);

  final FlutterSecureStorage _storage;

  // returns a stable device id — generated once and stored securely.
  // this is not a hardware id — it is a uuid we generate and keep.
  // cleared when the user uninstalls the app.
  Future<String> getDeviceId() async {
    final stored = await _storage.read(key: _kDeviceId);
    if (stored != null) return stored;

    final id = const Uuid().v4();
    await _storage.write(key: _kDeviceId, value: id);
    AppLogger.info('device: generated new device id');
    return id;
  }

  // returns the platform name — used for risk scoring context
  String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}

final deviceServiceProvider = Provider<DeviceService>((ref) {
  return DeviceService(const FlutterSecureStorage());
});