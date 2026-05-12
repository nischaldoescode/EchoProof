// notification service
// fetches and manages notifications
// replaces: notification_provider.dart (riverpod version)

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  RealtimeChannel? _channel;
  String? _subscribedUserId;

  int get unreadCount => _notifications.where((n) => !n.read).length;

  Future<void> loadNotifications() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

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

  Future<void> acceptFollowRequest(NotificationItem item) async {
    await _resolveFollowRequest(item, 'accepted');
  }

  Future<void> rejectFollowRequest(NotificationItem item) async {
    await _resolveFollowRequest(item, 'rejected');
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
    final nextData = {
      ...?item.data,
      'handled': true,
      'status': status,
    };

    await client
        .from('follow_requests')
        .update({'status': status}).eq('id', requestId);

    await client
        .from('notifications')
        .update({'read': true, 'data': nextData}).eq('id', item.id);

    await loadNotifications();
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
            if (_notifications.any((n) => n.id == item.id)) return;
            _notifications = [item, ..._notifications].take(50).toList();
            notifyListeners();
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
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      data: row['data'] as Map<String, dynamic>?,
    );
  }

  @override
  void dispose() {
    stopRealtime();
    super.dispose();
  }
}
