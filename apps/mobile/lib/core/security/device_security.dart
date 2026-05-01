// device security checks
// detects root, emulators, and debugging
// runs at app startup — warns user or restricts access

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';

abstract final class DeviceSecurity {
  // returns true if the device looks tampered or unsafe
  static bool get isCompromised {
    if (kDebugMode) return false; // never block during development
    return _isRooted || _isEmulator;
  }

  static bool get _isRooted {
    if (!Platform.isAndroid) return false;
    // check for common root indicators
    final rootPaths = [
      '/system/app/Superuser.apk',
      '/system/xbin/su',
      '/system/bin/su',
      '/sbin/su',
      '/data/local/su',
      '/data/local/bin/su',
      '/data/local/xbin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/tmp/su',
      '/system/app/SuperSU.apk',
      '/system/app/SuperSU',
      '/system/xbin/busybox',
    ];
    for (final path in rootPaths) {
      if (File(path).existsSync()) {
        AppLogger.warn('security: root indicator found at $path');
        return true;
      }
    }
    return false;
  }

  static bool get _isEmulator {
    // emulators have these characteristics
    final brand  = Platform.operatingSystemVersion.toLowerCase();
    return brand.contains('sdk') ||
           brand.contains('emulator') ||
           brand.contains('android sdk built for x86');
  }
}