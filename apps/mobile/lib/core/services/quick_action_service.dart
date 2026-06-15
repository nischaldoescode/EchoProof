// quick action service
// @params router receives native launcher shortcut navigation
// @params profileEnabled decides if the account shortcut should exist

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'avatar_service.dart';
import '../utils/logger.dart';

abstract final class QuickActionService {
  static const MethodChannel _channel = MethodChannel(
    'echoproof/quick_actions',
  );
  static bool _attached = false;
  static bool _profileEnabled = false;
  static String? _cachedProfileUserId;
  static String? _cachedAvatarUrl;
  static Uint8List? _cachedProfileIconBytes;
  static Map<String, Object>? _cachedProfileLabels;
  static DateTime? _lastAvatarLookupAt;

  static Future<void> attach(
    GoRouter router, {
    required bool profileEnabled,
  }) async {
    if (_attached || defaultTargetPlatform != TargetPlatform.android) return;
    _attached = true;
    _profileEnabled = profileEnabled;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shortcut') {
        _open(router, call.arguments as String?);
      }
    });

    try {
      await _syncNativeShortcuts(profileEnabled);
      final initial = await _channel.invokeMethod<String>('getInitialShortcut');
      if (initial != null && initial.trim().isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(
            const Duration(milliseconds: 420),
            () => _open(router, initial),
          );
        });
      }
    } catch (e) {
      AppLogger.warn('quick actions: setup skipped $e');
    }
  }

  static Future<void> syncForAuth({required bool profileEnabled}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (!profileEnabled && _profileEnabled == profileEnabled && _attached) {
      return;
    }
    _profileEnabled = profileEnabled;
    if (!profileEnabled) {
      _cachedProfileUserId = null;
      _cachedAvatarUrl = null;
      _cachedProfileIconBytes = null;
      _cachedProfileLabels = null;
      _lastAvatarLookupAt = null;
    }

    try {
      await _syncNativeShortcuts(profileEnabled);
    } catch (e) {
      AppLogger.warn('quick actions: sync skipped $e');
    }
  }

  static void _open(GoRouter router, String? id) {
    final route = switch (id) {
      'create_echo' => '/create',
      'profile' when _profileEnabled => '/profile',
      _ => null,
    };
    if (route == null) return;

    try {
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        router.go(route);
      });
    } catch (e) {
      AppLogger.warn('quick actions: route failed $e');
    }
  }

  static Future<void> _syncNativeShortcuts(bool profileEnabled) async {
    final profile = profileEnabled ? await _loadProfileShortcut() : null;
    await _channel.invokeMethod<void>('installShortcuts', {
      'includeProfile': profile != null,
      ...?profile,
    });
  }

  static Future<Map<String, Object>?> _loadProfileShortcut() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return null;

    if (_cachedProfileUserId != userId) {
      _cachedProfileUserId = userId;
      _cachedAvatarUrl = null;
      _cachedProfileIconBytes = null;
      _cachedProfileLabels = null;
      _lastAvatarLookupAt = null;
    }

    final now = DateTime.now();
    final lastLookup = _lastAvatarLookupAt;
    if (lastLookup != null &&
        now.difference(lastLookup) < const Duration(seconds: 20)) {
      return _withProfileIcon(
        _cachedProfileLabels ??
            {
              'profileShortLabel': 'Profile',
              'profileLongLabel': 'Your profile',
            },
        _cachedProfileIconBytes,
      );
    }
    _lastAvatarLookupAt = now;

    try {
      final row = await Supabase.instance.client
          .from('users_public')
          .select('avatar_url, display_name, username')
          .eq('id', userId)
          .maybeSingle();
      final username = (row?['username'] as String?)?.trim();
      final displayName = (row?['display_name'] as String?)?.trim();
      final profileName = _profileName(displayName, username);
      final labels = <String, Object>{
        'profileShortLabel': _shortLabel(profileName),
        'profileLongLabel': username != null && username.isNotEmpty
            ? '$profileName profile'
            : 'Your profile',
      };
      _cachedProfileLabels = labels;
      final avatarUrl = row?['avatar_url'] as String?;
      final fallbackUrl = AvatarService.defaultAvatarUrlFor(userId);
      final cleanUrl = avatarUrl?.trim().isNotEmpty == true
          ? avatarUrl!.trim()
          : fallbackUrl;
      if (cleanUrl.isEmpty || cleanUrl.contains('.svg')) {
        _cachedAvatarUrl = cleanUrl;
        _cachedProfileIconBytes = null;
        return labels;
      }
      if (_cachedAvatarUrl == cleanUrl && _cachedProfileIconBytes != null) {
        return _withProfileIcon(labels, _cachedProfileIconBytes);
      }

      final response = await http
          .get(Uri.parse(cleanUrl))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return labels;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('svg')) return labels;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty || bytes.length > 600 * 1024) return labels;

      _cachedAvatarUrl = cleanUrl;
      _cachedProfileIconBytes = Uint8List.fromList(bytes);
      return _withProfileIcon(labels, _cachedProfileIconBytes);
    } catch (e) {
      AppLogger.warn('quick actions: profile icon fallback $e');
      return _withProfileIcon(
        _cachedProfileLabels ??
            {
              'profileShortLabel': 'Profile',
              'profileLongLabel': 'Your profile',
            },
        _cachedProfileIconBytes,
      );
    }
  }

  static Map<String, Object> _withProfileIcon(
    Map<String, Object> labels,
    Uint8List? iconBytes,
  ) {
    if (iconBytes == null) return labels;
    return {...labels, 'profileIconBytes': iconBytes};
  }

  static String _profileName(String? displayName, String? username) {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return '@$handle';
    return 'Profile';
  }

  static String _shortLabel(String label) {
    final clean = label.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= 16) return clean;
    return '${clean.substring(0, 13)}...';
  }
}
