// notifications screen
// shows the user's notification history
// marks all as read when opened

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationProvider);

    // mark all as read when screen opens
    ref.listen(notificationProvider, (_, next) {
      if (next.hasValue) {
        ref.read(notificationProvider.notifier).markAllRead();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Notifications', style: AppTypography.textTheme.titleLarge),
      ),
      body: notificationsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.fernGreen),
        ),
        error: (e, _) => Center(
          child: Text('could not load notifications',
              style: AppTypography.textTheme.bodySmall),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications_none_outlined,
                      size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: AppSpacing.lg),
                  Text('No notifications yet',
                      style: AppTypography.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final n = notifications[i];
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                color: n.read ? AppColors.white : AppColors.fernGreenLight.withOpacity(0.4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NotificationIcon(type: n.type),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title,
                                style: AppTypography.textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(n.body,
                                style: AppTypography.textTheme.bodySmall),
                            const SizedBox(height: 4),
                            Text(
                              _timeAgo(n.createdAt),
                              style: AppTypography.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                      if (!n.read)
                        Container(
                          width: 7, height: 7,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: const BoxDecoration(
                            color: AppColors.fernGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'echo_verified'   => (Icons.verified_outlined,      AppColors.fernGreen),
      'trust_update'    => (Icons.trending_up_outlined,   AppColors.fernGreen),
      'report_resolved' => (Icons.shield_outlined,        AppColors.charcoal),
      'bond_settled'    => (Icons.link_outlined,          AppColors.fernGreen),
      'bond_contested'  => (Icons.link_off_outlined,      AppColors.sunsetCoral),
      _                 => (Icons.notifications_outlined, AppColors.textTertiary),
    };

    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}