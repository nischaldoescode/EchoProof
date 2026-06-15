// notification service
// fetches and manages notifications
// replaces: notification_provider.dart (riverpod version)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hyper_snackbar/hyper_snackbar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../core/utils/logger.dart';

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.createdAt,
    this.data,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime createdAt;
  final Map<String, dynamic>? data;

  NotificationItem copyWith({bool? read}) {
    return NotificationItem(
      id: id,
      type: type,
      title: title,
      body: body,
      read: read ?? this.read,
      createdAt: createdAt,
      data: data,
    );
  }
}

class NotificationService extends ChangeNotifier {
  List<NotificationItem> _notifications = [];
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final Set<String> _pendingSwipeDeleteIds = {};
  final Set<String> _locallyDeletedIds = {};

  RealtimeChannel? _channel;
  String? _subscribedUserId;
  bool _notifyQueued = false;
  bool _disposed = false;

  int get unreadCount => _notifications.where((n) => !n.read).length;

  @override
  void notifyListeners() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final canNotifyNow =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;
    if (canNotifyNow) {
      super.notifyListeners();
      return;
    }
    if (_notifyQueued) return;
    _notifyQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyQueued = false;
      if (_disposed) return;
      super.notifyListeners();
    });
  }

  bool get hasUnreadFollowerEcho =>
      _notifications.any((n) => !n.read && n.type == 'new_follower_echo');

  String _localDeletedKey(String userId) => 'notifications_deleted_v1_$userId';

  void _loadLocalDeletedIds(String userId) {
    if (!Hive.isBoxOpen('app_settings')) return;
    final raw = Hive.box('app_settings').get(_localDeletedKey(userId));
    _locallyDeletedIds
      ..clear()
      ..addAll(raw is List ? raw.whereType<String>() : const <String>[]);
  }

  void _rememberLocalDelete(String userId, String notificationId) {
    if (notificationId.isEmpty) return;
    _locallyDeletedIds.add(notificationId);
    if (!Hive.isBoxOpen('app_settings')) return;
    final compact = _locallyDeletedIds.take(200).toList(growable: false);
    unawaited(Hive.box('app_settings').put(_localDeletedKey(userId), compact));
  }

  Future<void> loadNotifications() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    _loadLocalDeletedIds(userId);

    _isLoading = true;
    notifyListeners();

    try {
      final rows = await client
          .from('notifications')
          .select('id, type, title, body, read, data, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      _notifications = (rows as List)
          .map((row) => _mapRow(row as Map<String, dynamic>))
          .where((item) => !_locallyDeletedIds.contains(item.id))
          .toList();
      startRealtime();

      AppLogger.info('notifications: loaded ${_notifications.length}');
    } catch (e) {
      AppLogger.error('notifications: load failed', e);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    await client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', userId)
        .eq('read', false);

    _notifications = _notifications.map((n) => n.copyWith(read: true)).toList();
    notifyListeners();
  }

  Future<bool> deleteNotification(
    NotificationItem item, {
    bool optimistic = true,
  }) async {
    final userId = _currentUserId();
    final index = _notifications.indexWhere((n) => n.id == item.id);
    if (index < 0) return true;

    if (optimistic) {
      final next = [..._notifications]..removeAt(index);
      _notifications = next;
      notifyListeners();
    }

    if (userId == null) {
      if (!optimistic) {
        final next = [..._notifications]..removeAt(index);
        _notifications = next;
        notifyListeners();
      }
      return true;
    }
    _rememberLocalDelete(userId, item.id);

    try {
      final deleted = await _deleteRemoteRow(item, userId);
      if (!deleted) {
        AppLogger.warn('notifications: remote delete returned no rows');
      }
      if (!optimistic) {
        final currentIndex = _notifications.indexWhere((n) => n.id == item.id);
        if (currentIndex >= 0) {
          final next = [..._notifications]..removeAt(currentIndex);
          _notifications = next;
          notifyListeners();
        }
      }
      return true;
    } catch (e) {
      AppLogger.warn('notifications: delete failed $e');
      if (optimistic && !_locallyDeletedIds.contains(item.id)) {
        final restored = [..._notifications];
        final restoreIndex = index.clamp(0, restored.length).toInt();
        restored.insert(restoreIndex, item);
        _notifications = restored;
        notifyListeners();
      }
      return false;
    }
  }

  void beginSwipeDelete(String notificationId) {
    _pendingSwipeDeleteIds.add(notificationId);
  }

  void cancelSwipeDelete(String notificationId) {
    _pendingSwipeDeleteIds.remove(notificationId);
  }

  void finishSwipeDelete(NotificationItem item) {
    _pendingSwipeDeleteIds.remove(item.id);
    final index = _notifications.indexWhere((n) => n.id == item.id);
    if (index < 0) return;

    final next = [..._notifications]..removeAt(index);
    _notifications = next;
    notifyListeners();
  }

  Future<bool> deleteNotificationRemote(NotificationItem item) async {
    final userId = _currentUserId();
    if (userId == null) return true;
    _rememberLocalDelete(userId, item.id);

    try {
      final deleted = await _deleteRemoteRow(item, userId);
      if (!deleted) {
        AppLogger.warn('notifications: remote delete returned no rows');
      }
      return true;
    } catch (e) {
      AppLogger.warn('notifications: remote delete failed $e');
      return true;
    }
  }

  Future<bool> _deleteRemoteRow(NotificationItem item, String userId) async {
    final client = Supabase.instance.client;
    try {
      final rpcDeleted =
          await client.rpc(
                'delete_own_notification',
                params: {'p_notification_id': item.id},
              )
              as bool?;
      if (rpcDeleted == true) return true;
      if (rpcDeleted == false) {
        return _notificationIsAlreadyGone(item.id, userId);
      }
    } catch (e) {
      AppLogger.warn('notifications: delete rpc unavailable $e');
    }

    // fallback for older schemas while the migration rolls out
    final rows = await client
        .from('notifications')
        .delete()
        .eq('id', item.id)
        .eq('user_id', userId)
        .select('id');
    if (rows.isNotEmpty) return true;
    return _notificationIsAlreadyGone(item.id, userId);
  }

  Future<bool> _notificationIsAlreadyGone(
    String notificationId,
    String userId,
  ) async {
    final rows = await Supabase.instance.client
        .from('notifications')
        .select('id')
        .eq('id', notificationId)
        .eq('user_id', userId)
        .limit(1);
    final alreadyGone = (rows as List).isEmpty;
    if (alreadyGone) {
      AppLogger.info('notifications: delete already absent $notificationId');
    }
    return alreadyGone;
  }

  Future<void> openNotification(
    BuildContext context,
    NotificationItem item,
  ) async {
    if (!item.read) {
      try {
        await Supabase.instance.client
            .from('notifications')
            .update({'read': true})
            .eq('id', item.id);
        _notifications = _notifications
            .map((n) => n.id == item.id ? n.copyWith(read: true) : n)
            .toList();
        notifyListeners();
      } catch (e) {
        AppLogger.warn('notifications: mark single read failed $e');
      }
    }

    final route = _routeFor(item);
    if (route == null || !context.mounted) return;
    GoRouter.of(context).push(route);
  }

  Future<void> markFollowerEchoesRead() async {
    final ids = _notifications
        .where((n) => !n.read && n.type == 'new_follower_echo')
        .map((n) => n.id)
        .toList();
    if (ids.isEmpty) return;

    _notifications = _notifications
        .map((n) => ids.contains(n.id) ? n.copyWith(read: true) : n)
        .toList();
    notifyListeners();

    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'read': true})
          .filter('id', 'in', '(${ids.join(',')})')
          .eq('type', 'new_follower_echo');
    } catch (e) {
      AppLogger.warn('notifications: follower echo dot clear failed $e');
    }
  }

  Future<void> acceptFollowRequest(NotificationItem item) async {
    await _resolveFollowRequest(item, 'accepted');
  }

  Future<void> rejectFollowRequest(NotificationItem item) async {
    await _resolveFollowRequest(item, 'rejected');
  }

  Future<void> markDeviceAlertHandled(
    NotificationItem item,
    String status,
  ) async {
    final nextData = {...?item.data, 'handled': true, 'status': status};

    await Supabase.instance.client
        .from('notifications')
        .update({'read': true, 'data': nextData})
        .eq('id', item.id);

    _notifications = _notifications
        .map(
          (n) => n.id == item.id
              ? NotificationItem(
                  id: n.id,
                  type: n.type,
                  title: n.title,
                  body: n.body,
                  read: true,
                  createdAt: n.createdAt,
                  data: nextData,
                )
              : n,
        )
        .toList();
    notifyListeners();
  }

  Future<bool> isFollowingActor(NotificationItem item) async {
    final actorId = _actorIdFor(item);
    final userId = _currentUserId();
    if (actorId == null || userId == null || actorId == userId) return true;

    try {
      final row = await Supabase.instance.client
          .from('user_follows')
          .select('follower_id')
          .eq('follower_id', userId)
          .eq('following_id', actorId)
          .maybeSingle();
      return row != null;
    } catch (e) {
      AppLogger.warn('notifications: follow-back state failed $e');
      return false;
    }
  }

  Future<String> followBack(NotificationItem item) async {
    final actorId = _actorIdFor(item);
    final userId = _currentUserId();
    if (actorId == null || userId == null || actorId == userId) {
      throw Exception('missing follower id');
    }

    final client = Supabase.instance.client;
    final alreadyFollowing = await isFollowingActor(item);
    final nextData = {...?item.data, 'followed_back': true};

    if (alreadyFollowing) {
      await client
          .from('notifications')
          .update({
            'data': {...nextData, 'follow_back_status': 'following'},
          })
          .eq('id', item.id);
      await loadNotifications();
      return 'following';
    }

    final actorProfile = await client
        .from('users_public')
        .select('is_public')
        .eq('id', actorId)
        .maybeSingle();
    final isPublic = actorProfile?['is_public'] as bool? ?? true;

    if (isPublic) {
      await client.from('user_follows').upsert({
        'follower_id': userId,
        'following_id': actorId,
      }, onConflict: 'follower_id,following_id');
      unawaited(_notifySocialEvent('new_follower', {'target_id': actorId}));
      await client
          .from('notifications')
          .update({
            'data': {...nextData, 'follow_back_status': 'following'},
          })
          .eq('id', item.id);
      await loadNotifications();
      return 'following';
    }

    final row = await client
        .from('follow_requests')
        .upsert({
          'requester_id': userId,
          'target_id': actorId,
          'status': 'pending',
        }, onConflict: 'requester_id,target_id')
        .select('id')
        .single();
    final requestId = row['id'] as String?;
    if (requestId != null) {
      unawaited(
        _notifySocialEvent('follow_request', {'request_id': requestId}),
      );
    }
    await client
        .from('notifications')
        .update({
          'data': {...nextData, 'follow_back_status': 'requested'},
        })
        .eq('id', item.id);
    await loadNotifications();
    return 'requested';
  }

  Future<void> _resolveFollowRequest(
    NotificationItem item,
    String status,
  ) async {
    final requestId = item.data?['request_id'] as String?;
    if (requestId == null || requestId.isEmpty) {
      throw Exception('missing follow request id');
    }

    final client = Supabase.instance.client;
    final nextData = {...?item.data, 'handled': true, 'status': status};

    await client
        .from('follow_requests')
        .update({'status': status})
        .eq('id', requestId);

    await client
        .from('notifications')
        .update({'read': true, 'data': nextData})
        .eq('id', item.id);

    if (status == 'accepted') {
      unawaited(
        _notifySocialEvent('follow_request_accepted', {
          'request_id': requestId,
        }),
      );
    }

    await loadNotifications();
  }

  String? _actorIdFor(NotificationItem item) {
    final actorId = item.data?['actor_id'];
    if (actorId is String && actorId.isNotEmpty) return actorId;

    final requesterId = item.data?['requester_id'];
    if (requesterId is String && requesterId.isNotEmpty) return requesterId;

    return null;
  }

  String? _currentUserId() {
    final client = Supabase.instance.client;
    return client.auth.currentSession?.user.id ?? client.auth.currentUser?.id;
  }

  void startRealtime() {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;
    if (_subscribedUserId == userId && _channel != null) return;

    stopRealtime();
    _subscribedUserId = userId;

    _channel = client
        .channel('notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final item = _mapRow(payload.newRecord);
            if (_locallyDeletedIds.contains(item.id)) return;
            if (_notifications.any((n) => n.id == item.id)) return;
            _notifications = [item, ..._notifications].take(50).toList();
            notifyListeners();
            _showForegroundBanner(item);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final updated = _mapRow(payload.newRecord);
            _notifications = _notifications
                .map((n) => n.id == updated.id ? updated : n)
                .toList();
            notifyListeners();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final id = payload.oldRecord['id'];
            if (id is! String || id.isEmpty) return;
            if (_pendingSwipeDeleteIds.contains(id)) return;
            _notifications = _notifications
                .where((notification) => notification.id != id)
                .toList();
            notifyListeners();
          },
        )
        .subscribe();
  }

  void stopRealtime() {
    final channel = _channel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    _channel = null;
    _subscribedUserId = null;
  }

  NotificationItem _mapRow(Map<String, dynamic> row) {
    return NotificationItem(
      id: row['id'] as String,
      type: row['type'] as String,
      title: row['title'] as String,
      body: row['body'] as String,
      read: row['read'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      data: row['data'] as Map<String, dynamic>?,
    );
  }

  Future<void> _notifySocialEvent(
    String event,
    Map<String, dynamic> body,
  ) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'notify-social-event',
        body: {'event': event, ...body},
      );
    } catch (e) {
      AppLogger.warn('notifications: social event notify failed $e');
    }
  }

  void _showForegroundBanner(NotificationItem item) {
    final context = HyperSnackbar.navigatorKey.currentContext;
    if (context == null) return;

    final route = _routeFor(item);
    final topPadding = MediaQuery.maybeOf(context)?.viewPadding.top ?? 0;
    final (icon, color) = _iconFor(item.type);

    try {
      HyperSnackbar.show(
        title: item.title,
        message: item.body,
        snackPosition: HyperSnackPosition.top,
        snackStyle: HyperSnackStyle.floating,
        displayMode: HyperSnackDisplayMode.queue,
        maxVisibleCount: 1,
        displayDuration: const Duration(seconds: 4),
        backgroundColor: AppColors.charcoal,
        textColor: AppColors.white,
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: AppSpacing.radiusMd,
        margin: EdgeInsets.fromLTRB(14, topPadding + 10, 14, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        maxWidth: 520,
        alignment: Alignment.topCenter,
        icon: Icon(icon, color: color, size: 20),
        showCloseButton: true,
        animationType: HyperSnackAnimationType.scale,
        action: route == null
            ? null
            : HyperSnackAction(
                label: 'Open',
                onPressed: () {
                  final navContext = HyperSnackbar.navigatorKey.currentContext;
                  if (navContext == null) return;
                  GoRouter.of(navContext).push(route);
                },
              ),
      );
    } catch (e, stack) {
      AppLogger.error('notifications: foreground banner failed', e, stack);
    }
  }

  String? _routeFor(NotificationItem item) {
    final rawRoute = item.data?['route'];
    if (rawRoute is String && rawRoute.trim().isNotEmpty) return rawRoute;

    final echoId = item.data?['echo_id'];
    if (echoId is String && echoId.trim().isNotEmpty) {
      return '/feed/echo/${Uri.encodeComponent(echoId)}';
    }

    if (item.type == 'follow_request' ||
        item.type == 'account_device_login_attempt') {
      return '/notifications';
    }
    return null;
  }

  (IconData, Color) _iconFor(String type) => switch (type) {
    'echo_verified' => (Icons.verified_outlined, AppColors.fernGreen),
    'identity_verified' => (Icons.verified_user_rounded, AppColors.fernGreen),
    'echo_supported' => (Icons.thumb_up_alt_outlined, AppColors.fernGreen),
    'echo_challenged' => (Icons.report_problem_outlined, AppColors.sunsetCoral),
    'context_requested' => (
      Icons.fact_check_outlined,
      AppColors.statusUnderReview,
    ),
    'context_like' => (Icons.favorite_border_rounded, AppColors.fernGreen),
    'echo_reply' ||
    'reply_reply' => (Icons.reply_outlined, AppColors.fernGreen),
    'reply_like' => (Icons.favorite_outline_rounded, AppColors.fernGreen),
    'follow_request' => (Icons.person_add_alt_1_rounded, AppColors.fernGreen),
    'follow_request_accepted' ||
    'new_follower' => (Icons.how_to_reg_rounded, AppColors.fernGreen),
    'new_follower_echo' => (Icons.dynamic_feed_outlined, AppColors.fernGreen),
    'account_device_login_attempt' => (
      Icons.phonelink_lock_rounded,
      AppColors.sunsetCoral,
    ),
    'content_removed' ||
    'echo_moderation' => (Icons.shield_outlined, AppColors.sunsetCoral),
    _ => (Icons.notifications_outlined, AppColors.fernGreen),
  };

  @override
  void dispose() {
    _disposed = true;
    stopRealtime();
    super.dispose();
  }
}
