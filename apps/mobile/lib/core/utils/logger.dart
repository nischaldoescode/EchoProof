// app logger
// wraps dart developer log with level prefixes
// in release builds logging is disabled so diagnostics do not leak to store builds.

import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

abstract final class AppLogger {
  static void audit(String message) {
    if (!kDebugMode) return;
    debugPrint('echoproof audit: $message');
    dev.log('[AUDIT] $message', name: 'echoproof');
  }

  static void info(String message) {
    if (!kDebugMode) return;
    debugPrint('echoproof info: $message');
    dev.log('[INFO] $message', name: 'echoproof');
  }

  static void warn(String message) {
    if (!kDebugMode) return;
    debugPrint('echoproof warn: $message');
    dev.log('[WARN] $message', name: 'echoproof');
  }

  static void error(String message, [Object? error, StackTrace? stack]) {
    if (!kDebugMode) return;
    debugPrint('echoproof error: $message');
    dev.log(
      '[ERROR] $message',
      name: 'echoproof',
      error: error,
      stackTrace: stack,
    );
  }

  static void debug(String message) {
    if (!kDebugMode) return;
    debugPrint('echoproof debug: $message');
    dev.log('[DEBUG] $message', name: 'echoproof');
  }
}
