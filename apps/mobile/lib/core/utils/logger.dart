// app logger
// wraps dart's developer log with level prefixes
// short, professional, no emoji
// in release builds: only errors are logged

import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

abstract final class AppLogger {
  static void info(String message) {
    if (kDebugMode) {
      dev.log('[INFO] $message', name: 'echoproof');
    }
  }

  static void warn(String message) {
    if (kDebugMode) {
      dev.log('[WARN] $message', name: 'echoproof');
    }
  }

  static void error(String message, [Object? error, StackTrace? stack]) {
    dev.log('[ERROR] $message', name: 'echoproof', error: error, stackTrace: stack);
  }

  static void debug(String message) {
    if (kDebugMode) {
      dev.log('[DEBUG] $message', name: 'echoproof');
    }
  }
}