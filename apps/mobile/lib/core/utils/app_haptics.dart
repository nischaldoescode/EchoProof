// app haptics
// @params event key cooldown

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

abstract final class AppHaptics {
  static final Map<String, DateTime> _lastByKey = {};
  static bool? _hasVibrator;
  static bool? _hasAmplitude;

  static Future<void> selection({String key = 'selection'}) {
    return _pulse(
      key: key,
      durationMs: 9,
      amplitude: 28,
      cooldownMs: 90,
      fallback: HapticFeedback.selectionClick,
    );
  }

  static Future<void> gameStart() {
    return _pulse(
      key: 'game_start',
      durationMs: 12,
      amplitude: 42,
      cooldownMs: 350,
      fallback: HapticFeedback.selectionClick,
    );
  }

  static Future<void> gameReflector() {
    return _pulse(
      key: 'game_reflector',
      durationMs: 10,
      amplitude: 38,
      cooldownMs: 110,
      fallback: HapticFeedback.selectionClick,
    );
  }

  static Future<void> gamePaddle({required bool perfect, required int combo}) {
    if (perfect || combo >= 4) {
      return _pulse(
        key: 'game_paddle_strong',
        durationMs: 17,
        amplitude: combo >= 6 ? 78 : 62,
        cooldownMs: 130,
        fallback: HapticFeedback.mediumImpact,
      );
    }
    return _pulse(
      key: 'game_paddle',
      durationMs: 11,
      amplitude: 34,
      cooldownMs: 95,
      fallback: HapticFeedback.lightImpact,
    );
  }

  static Future<void> gameNearMiss() {
    return _pulse(
      key: 'game_near_miss',
      durationMs: 14,
      amplitude: 54,
      cooldownMs: 260,
      fallback: HapticFeedback.mediumImpact,
    );
  }

  static Future<void> gameFocus() {
    return _pattern(
      key: 'game_focus',
      pattern: const [0, 14, 44, 18],
      intensities: const [0, 62, 0, 74],
      cooldownMs: 4500,
      fallback: HapticFeedback.mediumImpact,
    );
  }

  static Future<void> gameOver() {
    return _pattern(
      key: 'game_over',
      pattern: const [0, 24, 64, 32],
      intensities: const [0, 82, 0, 92],
      cooldownMs: 1200,
      fallback: HapticFeedback.heavyImpact,
    );
  }

  static Future<void> criticalOpen({String key = 'critical_open'}) {
    return _pulse(
      key: key,
      durationMs: 20,
      amplitude: 66,
      cooldownMs: 900,
      fallback: HapticFeedback.mediumImpact,
    );
  }

  static Future<void> criticalConfirm({String key = 'critical_confirm'}) {
    return _pulse(
      key: key,
      durationMs: 18,
      amplitude: 78,
      cooldownMs: 700,
      fallback: HapticFeedback.mediumImpact,
    );
  }

  static Future<void> caution({String key = 'caution'}) {
    return _pulse(
      key: key,
      durationMs: 14,
      amplitude: 54,
      cooldownMs: 700,
      fallback: HapticFeedback.lightImpact,
    );
  }

  static Future<void> _pulse({
    required String key,
    required int durationMs,
    required int amplitude,
    required int cooldownMs,
    required Future<void> Function() fallback,
  }) async {
    if (!_canRun(key, cooldownMs)) return;
    if (!_usesNativeVibration) {
      await _fallback(fallback);
      return;
    }

    try {
      final hasVibrator = await _deviceHasVibrator();
      if (!hasVibrator) {
        await _fallback(fallback);
        return;
      }
      final hasAmplitude = await _deviceHasAmplitude();
      await Vibration.vibrate(
        duration: durationMs,
        amplitude: hasAmplitude ? amplitude.clamp(1, 255) : -1,
      );
    } catch (_) {
      await _fallback(fallback);
    }
  }

  static Future<void> _pattern({
    required String key,
    required List<int> pattern,
    required List<int> intensities,
    required int cooldownMs,
    required Future<void> Function() fallback,
  }) async {
    if (!_canRun(key, cooldownMs)) return;
    if (!_usesNativeVibration) {
      await _fallback(fallback);
      return;
    }

    try {
      final hasVibrator = await _deviceHasVibrator();
      if (!hasVibrator) {
        await _fallback(fallback);
        return;
      }
      final hasAmplitude = await _deviceHasAmplitude();
      await Vibration.vibrate(
        pattern: pattern,
        intensities: hasAmplitude ? intensities : const [],
      );
    } catch (_) {
      await _fallback(fallback);
    }
  }

  static bool get _usesNativeVibration {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  static bool _canRun(String key, int cooldownMs) {
    final now = DateTime.now();
    final last = _lastByKey[key];
    if (last != null && now.difference(last).inMilliseconds < cooldownMs) {
      return false;
    }
    _lastByKey[key] = now;
    return true;
  }

  static Future<bool> _deviceHasVibrator() async {
    final cached = _hasVibrator;
    if (cached != null) return cached;
    final value = await Vibration.hasVibrator().timeout(
      const Duration(milliseconds: 220),
      onTimeout: () => false,
    );
    _hasVibrator = value;
    return value;
  }

  static Future<bool> _deviceHasAmplitude() async {
    final cached = _hasAmplitude;
    if (cached != null) return cached;
    final value = await Vibration.hasAmplitudeControl().timeout(
      const Duration(milliseconds: 220),
      onTimeout: () => false,
    );
    _hasAmplitude = value;
    return value;
  }

  static Future<void> _fallback(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // some emulators and web shells ignore haptics
    }
  }
}
