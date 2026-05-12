// Device security checks.
// Detects common root/jailbreak indicators as a soft deterrent.
// These are speed bumps, not walls — a determined attacker can bypass them.
// The real security is in Supabase RLS + server-side validation.
// Never rely on client-side security as the sole protection for sensitive data.

import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/logger.dart';

abstract final class DeviceSecurity {
  // Returns true if the device appears tampered or unsafe.
  // Never blocks in debug mode.
  static bool get isCompromised {
    if (kDebugMode) return false;
    if (Platform.isAndroid) return _isAndroidRooted;
    if (Platform.isIOS) return _isIosJailbroken;
    return false;
    // Note: Emulator check removed — legitimate developers and some QA
    // setups run on emulators. Block only in production if needed.
  }

  static bool get _isAndroidRooted {
    // Check for common su binary locations.
    // Note: Magisk Hide can conceal these — this is a basic deterrent.
    const rootPaths = [
      '/system/app/Superuser.apk',
      '/system/xbin/su',
      '/system/bin/su',
      '/system/bin/.ext/su',
      '/sbin/su',
      '/sbin/.magisk',
      '/data/adb/magisk',
      '/data/local/su',
      '/data/local/bin/su',
      '/data/local/xbin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/tmp/su',
      '/system/app/SuperSU.apk',
      '/system/xbin/busybox',
      '/cache/magisk.log',
    ];

    if (_hasAnyPath(rootPaths, 'root')) return true;

    // Check for test-keys build signature (common on custom ROMs).
    try {
      final buildProp = File('/system/build.prop').readAsStringSync();
      if (buildProp.contains('test-keys')) {
        AppLogger.warn('security: test-keys build detected');
        return true;
      }
    } catch (_) {}

    return false;
  }

  static bool get _isIosJailbroken {
    const jailbreakPaths = [
      '/Applications/Cydia.app',
      '/Applications/Sileo.app',
      '/Applications/Zebra.app',
      '/Library/MobileSubstrate/MobileSubstrate.dylib',
      '/bin/bash',
      '/usr/sbin/sshd',
      '/etc/apt',
      '/private/var/lib/apt',
      '/private/var/stash',
    ];

    return _hasAnyPath(jailbreakPaths, 'jailbreak');
  }

  static bool _hasAnyPath(List<String> paths, String label) {
    for (final path in paths) {
      try {
        if (FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound) {
          AppLogger.warn('security: $label indicator at $path');
          return true;
        }
      } catch (_) {
        // File access may throw on some devices — ignore.
      }
    }
    return false;
  }

  // Soft emulator check — used for logging only, not blocking.
  static bool get isEmulator {
    if (!Platform.isAndroid) return false;
    final v = Platform.operatingSystemVersion.toLowerCase();
    return v.contains('sdk') ||
        v.contains('emulator') ||
        v.contains('android sdk built for x86');
  }
}
