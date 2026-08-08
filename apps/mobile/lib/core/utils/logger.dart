// app logger
// wraps dart developer log with level prefixes
// in release builds logging is disabled so diagnostics do not leak to store builds.

import 'dart:developer' as dev;
import 'package:flutter/foundation.dart';

import '../services/error_monitoring_service.dart';

abstract final class AppLogger {
  static void audit(String message) {
    final safeMessage = _friendly(message);
    if (!kDebugMode) return;
    debugPrint('echoproof audit: $safeMessage');
    dev.log('$safeMessage', name: 'echoproof');
  }

  static void info(String message) {
    final safeMessage = _friendly(message);
    if (!kDebugMode) return;
    debugPrint('echoproof info: $safeMessage');
    dev.log('[INFO] $safeMessage', name: 'echoproof');
  }

  static void warn(String message) {
    final safeMessage = _friendly(message);
    ErrorMonitoringService.captureBreadcrumb('warn', safeMessage);
    if (!kDebugMode) return;
    debugPrint('echoproof warn: $safeMessage');
    dev.log('warn,: $safeMessage', name: 'echoproof');
  }

  static void error(String message, [Object? error, StackTrace? stack]) {
    final safeMessage = _friendly(message);
    if (isTransientNetworkError(error, message) ||
        isTransientNetworkError(error, safeMessage)) {
      final breadcrumb = _transientNetworkBreadcrumb(safeMessage, error);
      ErrorMonitoringService.captureBreadcrumb('warn', breadcrumb);
      if (!kDebugMode) return;
      debugPrint('echoproof warn: $breadcrumb');
      dev.log('warn,: $breadcrumb', name: 'echoproof', error: error);
      return;
    }

    ErrorMonitoringService.captureError(
      safeMessage,
      error: error,
      stack: stack,
    );
    if (!kDebugMode) return;
    debugPrint('echoproof error: $safeMessage');
    dev.log(
      'error:, $safeMessage',
      name: 'echoproof',
      error: error,
      stackTrace: stack,
    );
  }

  static void debug(String message) {
    final safeMessage = _friendly(message);
    if (!kDebugMode) return;
    debugPrint('echoproof debug: $safeMessage');
    dev.log('debug:, $safeMessage', name: 'echoproof');
  }

  /// true for short-lived transport failures that should stay as breadcrumbs.
  ///
  /// connection resets, dns misses, aborted sockets, and timeouts are common
  /// when android moves the app to the background, the screen turns off, wifi
  /// changes, private dns blocks lookup, or supabase closes an idle socket. they
  /// are useful context, but sending each one as a sentry issue makes real app
  /// bugs harder to see.
  static bool isTransientNetworkError(Object? error, [String? message]) {
    final text = '${message ?? ''} ${error ?? ''}'.toLowerCase();
    if (text.trim().isEmpty) return false;

    final hasNetworkContext =
        text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('dioexception') ||
        text.contains('xmlhttprequest') ||
        text.contains('network request') ||
        text.contains('failed host lookup') ||
        text.contains('connection reset') ||
        text.contains('connection abort') ||
        text.contains('connection timed out') ||
        text.contains('network is unreachable') ||
        text.contains('offline');
    if (!hasNetworkContext) return false;

    return text.contains('failed host lookup') ||
        text.contains('no address associated with hostname') ||
        text.contains('connection reset by peer') ||
        text.contains('software caused connection abort') ||
        text.contains('connection closed before full header') ||
        text.contains('connection timed out') ||
        text.contains('network is unreachable') ||
        text.contains('network unreachable') ||
        text.contains('errno = 7') ||
        text.contains('errno = 103') ||
        text.contains('errno = 104') ||
        text.contains('timeoutexception') ||
        text.contains('offline');
  }

  static String _transientNetworkBreadcrumb(String message, Object? error) {
    final areaBreak = message.indexOf(':');
    final area = areaBreak > 0 ? message.substring(0, areaBreak) : 'network';
    final text = '$message ${error ?? ''}'.toLowerCase();
    final reason =
        text.contains('failed host lookup') ||
            text.contains('no address associated with hostname')
        ? 'dns unavailable'
        : text.contains('connection reset by peer') ||
              text.contains('errno = 104')
        ? 'connection reset'
        : text.contains('software caused connection abort') ||
              text.contains('errno = 103')
        ? 'connection aborted'
        : text.contains('timeoutexception') || text.contains('timed out')
        ? 'timeout'
        : text.contains('offline') || text.contains('network is unreachable')
        ? 'offline'
        : 'temporary failure';
    return '$area: transient network skipped $reason';
  }

  static String _friendly(String message) {
    return message
        .replaceAllMapped(
          RegExp(r'\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\b'),
          (match) => match.group(0)!.replaceAll('_', ' '),
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
