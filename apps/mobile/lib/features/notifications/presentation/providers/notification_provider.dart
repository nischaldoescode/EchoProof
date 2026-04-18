// notification provider
// fetches unread notifications for the current user
// marks them as read when viewed

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

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

  final String             id;
  final String             type;
  final String             title;
  final String             body;
  final bool               read;
  final DateTime           createdAt;
  final Map<String, dynamic>? data;
}

class NotificationNotifier extends AsyncNotifier<List<NotificationItem>> {
  @override
  Future<List<NotificationItem>> build() async {
    return _fetchNotifications();
  }

  Future<List<NotificationItem>> _fetchNotifications() async {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await client
        .from('notifications')
        .select('id, type, title, body, read, data, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    return (rows as List).map((row) => NotificationItem(
      id:        row['id'] as String,
      type:      row['type'] as String,
      title:     row['title'] as String,
      body:      row['body'] as String,
      read:      row['read'] as bool? ?? false,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now(),
      data:      row['data'] as Map<String, dynamic>?,
    )).toList();
  }

  // marks all unread notifications as read
  Future<void> markAllRead() async {
    final client = ref.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    if (userId == null) return;

    await client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', userId)
        .eq('read', false);

    state = AsyncData(
      (state.valueOrNull ?? []).map((n) => NotificationItem(
        id: n.id, type: n.type, title: n.title,
        body: n.body, read: true, createdAt: n.createdAt, data: n.data,
      )).toList(),
    );
  }

  int get unreadCount =>
      (state.valueOrNull ?? []).where((n) => !n.read).length;
}

final notificationProvider =
    AsyncNotifierProvider<NotificationNotifier, List<NotificationItem>>(
  NotificationNotifier.new,
);

final unreadCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationProvider).valueOrNull ?? [];
  return notifications.where((n) => !n.read).length;
});