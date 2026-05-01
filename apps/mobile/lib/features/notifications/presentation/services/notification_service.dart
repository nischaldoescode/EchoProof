// notification service
// fetches and manages notifications
// replaces: notification_provider.dart (riverpod version)

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/logger.dart';
import 'package:flutter/painting.dart' show Color;
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

  final String              id;
  final String              type;
  final String              title;
  final String              body;
  final bool                read;
  final DateTime            createdAt;
  final Map<String, dynamic>? data;

  NotificationItem copyWith({bool? read}) {
    return NotificationItem(
      id:        id,
      type:      type,
      title:     title,
      body:      body,
      read:      read ?? this.read,
      createdAt: createdAt,
      data:      data,
    );
  }
}

class NotificationService extends ChangeNotifier {
  List<NotificationItem> _notifications = [];
  List<NotificationItem> get notifications => List.unmodifiable(_notifications);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

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

      _notifications = (rows as List).map((row) => NotificationItem(
        id:        row['id'] as String,
        type:      row['type'] as String,
        title:     row['title'] as String,
        body:      row['body'] as String,
        read:      row['read'] as bool? ?? false,
        createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
        data:      row['data'] as Map<String, dynamic>?,
      )).toList();

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
}