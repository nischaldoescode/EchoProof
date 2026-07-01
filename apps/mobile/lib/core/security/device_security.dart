// device security checks
// detects common root/jailbreak indicators as a soft deterrent
// these are speed bumps, not walls a determined attacker can bypass them
// the real security is in supabase rls + server-side validation
// never rely on client-side security as the sole protection for sensitive data
// magisk, zygisk, revanced-style patches, and custom roms can spoof many local
// checks. use a server-verified play integrity verdict for high-risk actions
// when the backend needs stronger proof of app and device integrity.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/logger.dart';

abstract final class DeviceSecurity {
  static const _channel = MethodChannel('echoproof/security_signals');
  static const _expectedAndroidCertSha256 = String.fromEnvironment(
    'ECHOPROOF_ANDROID_CERT_SHA256',
  );
  static const _requirePlayInstaller = bool.fromEnvironment(
    'ECHOPROOF_REQUIRE_PLAY_INSTALLER',
    defaultValue: true,
  );
  static const _strictDeviceSecurity = bool.fromEnvironment(
    'ECHOPROOF_STRICT_DEVICE_SECURITY',
    defaultValue: true,
  );

  // returns true if the device appears tampered or unsafe
  // never blocks in debug mode
  static bool get isCompromised {
    if (kDebugMode) return false;
    if (Platform.isAndroid) return _isAndroidRooted;
    if (Platform.isIOS) return _isIosJailbroken;
    return false;
    // note: emulator check removed legitimate developers and some qa
    // setups run on emulators. block only in production if needed
  }

  static bool get _isAndroidRooted {
    // check for common su binary locations
    // note: magisk hide can conceal these this is a basic deterrent
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
      '/data/adb/modules',
      '/data/adb/zygisk',
      '/data/adb/ksu',
      '/data/adb/ap',
      '/data/adb/shamiko',
      '/system/bin/magisk',
      '/system/xbin/daemonsu',
      '/su/bin/su',
      '/system/bin/.ext/.su',
      '/system/etc/init.d/99SuperSUDaemon',
    ];

    if (_hasAnyPath(rootPaths, 'root')) return true;

    // check for test-keys build signature (common on custom roms)
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
        // file access may throw on some devices ignore
      }
    }
    return false;
  }

  // soft emulator check used for logging only, not blocking
  static bool get isEmulator {
    if (!Platform.isAndroid) return false;
    final v = Platform.operatingSystemVersion.toLowerCase();
    return v.contains('sdk') ||
        v.contains('emulator') ||
        v.contains('android sdk built for x86');
  }

  static Future<void> enforceSecureWindow() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('enforceSecureWindow');
    } catch (_) {
      // native secure flag is best effort during engine startup
      // mainactivity applies it before flutter draws on android
    }
  }

  /// returns the android installer package without running the full security scan.
  ///
  /// this is intentionally narrow because launch and resume checks call it more
  /// often than the lockdown gate. root, hook, mount, and signature probes stay
  /// in inspect(), while play-only features can cheaply skip themselves on adb,
  /// shared apk, missing installer, and device-restore installs.
  static Future<String> androidInstallerPackageName() async {
    if (!Platform.isAndroid) return '';
    try {
      final installer = await _channel.invokeMethod<String>(
        'installerPackageName',
      );
      return installer ?? '';
    } catch (e) {
      AppLogger.warn('security: installer lookup failed $e');
      return '';
    }
  }

  static bool isTrustedPlayInstallerPackage(String installer) {
    return _trustedPlayInstaller(installer);
  }

  static Future<DeviceSecurityReport> inspect() async {
    if (kDebugMode || !_strictDeviceSecurity) {
      return const DeviceSecurityReport(compromised: false);
    }

    final reasons = <String>[];
    final native = Platform.isAndroid ? await _androidSignals() : const {};

    if (Platform.isAndroid) {
      final packageName = _asString(native['packageName']);
      if (packageName.isNotEmpty && packageName != 'com.echoproof.app') {
        reasons.add('package_mismatch');
      }

      if (_asBool(native['debuggable'])) {
        reasons.add('debuggable_release');
      }
      if (_asBool(native['debuggerConnected'])) {
        reasons.add('debugger_attached');
      }

      final installer = _asString(native['installerPackageName']);
      if (_requirePlayInstaller && !_trustedPlayInstaller(installer)) {
        reasons.add(
          installer.isEmpty ? 'installer_missing' : 'installer_untrusted',
        );
      }

      final hooks = _asStringList(native['hookIndicators']);
      if (hooks.isNotEmpty) reasons.add('runtime_hook_${hooks.join("_")}');

      final nativeRoots = _asStringList(native['rootIndicators']);
      if (nativeRoots.isNotEmpty) reasons.add('native_root_indicator');

      final mounts = _asStringList(native['mountIndicators']);
      if (mounts.isNotEmpty) reasons.add('modified_mount_state');

      final buildTags = _asStringList(native['dangerousBuildTags']);
      if (buildTags.isNotEmpty) reasons.add('unsafe_android_build');

      if (_asBool(native['suProbe'])) {
        reasons.add('su_binary_available');
      }

      final tracerPid = _asInt(native['tracerPid']);
      if (tracerPid > 0) {
        reasons.add('native_tracer_attached');
      }

      final expected = _normalizeHash(_expectedAndroidCertSha256);
      if (expected.isNotEmpty) {
        final actual = _asStringList(
          native['signingCertificateSha256'],
        ).map(_normalizeHash).toSet();
        if (!actual.contains(expected)) {
          reasons.add('signature_mismatch');
        }
      }
    }

    if (isCompromised) reasons.add('device_compromised');

    if (reasons.isNotEmpty) {
      AppLogger.warn('security: blocked device reasons=${reasons.join(",")}');
    }

    return DeviceSecurityReport(
      compromised: reasons.isNotEmpty,
      reasons: reasons,
      nativeSignals: Map<String, Object?>.from(native),
    );
  }

  static Future<Map<Object?, Object?>> _androidSignals() async {
    try {
      final result = await _channel.invokeMethod<Object?>('securitySignals');
      if (result is Map) return Map<Object?, Object?>.from(result);
    } catch (e) {
      AppLogger.warn('security: native signal check failed $e');
    }
    return const {};
  }

  static bool _trustedPlayInstaller(String installer) {
    if (installer.isEmpty) return false;
    return installer == 'com.android.vending';
  }

  static bool _asBool(Object? value) => value == true;

  static String _asString(Object? value) => value is String ? value : '';

  static int _asInt(Object? value) => value is int ? value : 0;

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return value.whereType<String>().toList(growable: false);
    }
    return const [];
  }

  static String _normalizeHash(String value) {
    return value
        .replaceAll(':', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .trim()
        .toUpperCase();
  }
}

class DeviceSecurityReport {
  const DeviceSecurityReport({
    required this.compromised,
    this.reasons = const [],
    this.nativeSignals = const {},
  });

  final bool compromised;
  final List<String> reasons;
  final Map<String, Object?> nativeSignals;

  bool get hasInstallIntegrityIssue => reasons.any(_installIntegrityReasons);

  bool get hasDeviceIntegrityIssue =>
      reasons.any((reason) => !_installIntegrityReasons(reason));

  static bool _installIntegrityReasons(String reason) {
    return reason == 'installer_missing' ||
        reason == 'installer_untrusted' ||
        reason == 'signature_mismatch' ||
        reason == 'package_mismatch';
  }
}
