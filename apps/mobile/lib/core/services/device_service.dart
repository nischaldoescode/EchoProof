// device service
// generates a stable device fingerprint

import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import '../utils/logger.dart';

const _kDeviceId = 'device_fingerprint';

class DeviceService {
  DeviceService(this._storage);

  final FlutterSecureStorage _storage;

  Future<String> getDeviceId() async {
    final stored = await _storage.read(key: _kDeviceId);
    if (stored != null) return stored;

    final id = const Uuid().v4();
    await _storage.write(key: _kDeviceId, value: id);
    AppLogger.info('device: generated new device id');

    return id;
  }

  String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }
}
