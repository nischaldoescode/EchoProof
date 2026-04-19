// notifications screen
// shows notification history, marks all as read on open
// uses NotificationService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final service = context.read<NotificationService>();
      service.loadNotifications().then((_) => service.markAllRead());
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Notifications', style: AppTypography.textTheme.titleLarge),
      ),
      body: service.isLoading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.fernGreen,
              ),
            )
          : service.notifications.isEmpty
              ? _EmptyNotifications()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: service.notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final n = service.notifications[i];
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: n.read
                          ? AppColors.white
                          : AppColors.fernGreenLight.withOpacity(0.4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical:   AppSpacing.md,
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
                                  Text(
                                    n.title,
                                    style: AppTypography.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    n.body,
                                    style: AppTypography.textTheme.bodySmall,
                                  ),
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
                                width:  7,
                                height: 7,
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

class _EmptyNotifications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_none_outlined,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No notifications yet',
            style: AppTypography.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}