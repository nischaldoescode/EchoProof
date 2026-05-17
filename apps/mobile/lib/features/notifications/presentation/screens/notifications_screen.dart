// notifications screen
// shows notification history, marks all as read on open
// uses NotificationService via provider — no riverpod

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../services/notification_service.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../app/app.dart';
import '../../../../core/utils/snack.dart';
import '../../../../core/localization/app_copy.dart';

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
      service.loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();

    return SwipeNavigationWrapper(
      currentLocation: '/notifications',
      child: ExitConfirmWrapper(
        child: Scaffold(
          backgroundColor: AppColors.white,
          appBar: AppBar(
            actions: [
              IconButton(
                icon: const Icon(Icons.done_all_rounded),
                tooltip: context.l('Mark all read'),
                onPressed:
                    service.unreadCount == 0 ? null : service.markAllRead,
              ),
            ],
            title: Text(context.l('Notifications'),
                style: AppTypography.textTheme.titleLarge),
            automaticallyImplyLeading: false,
          ),
          bottomNavigationBar:
              const AppBottomNav(currentLocation: '/notifications'),
          body: service.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.fernGreen,
                  ),
                )
              : service.notifications.isEmpty
                  ? RefreshIndicator(
                      color: AppColors.fernGreen,
                      onRefresh: service.loadNotifications,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 200),
                          _EmptyNotifications(),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.fernGreen,
                      onRefresh: service.loadNotifications,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        itemCount: service.notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final n = service.notifications[i];
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            color: n.read
                                ? AppColors.white
                                : AppColors.fernGreenLight
                                    .withValues(alpha: 0.4),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          n.title,
                                          style: AppTypography
                                              .textTheme.titleSmall,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          n.body,
                                          style:
                                              AppTypography.textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _timeAgo(n.createdAt),
                                          style: AppTypography
                                              .textTheme.labelMedium,
                                        ),
                                        if (n.type == 'follow_request' &&
                                            n.data?['handled'] != true) ...[
                                          const SizedBox(height: AppSpacing.sm),
                                          _FollowRequestActions(item: n),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (!n.read)
                                    Container(
                                      width: 7,
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
                    ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
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
            context.l('No notifications yet'),
            style: AppTypography.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowRequestActions extends StatelessWidget {
  const _FollowRequestActions({required this.item});
  final NotificationItem item;

  @override
  Widget build(BuildContext context) {
    final service = context.read<NotificationService>();

    return Row(
      children: [
        TextButton.icon(
          onPressed: () async {
            try {
              await service.acceptFollowRequest(item);
              if (context.mounted) {
                showSuccessSnack(context, context.l('Request accepted'));
              }
            } catch (_) {
              if (context.mounted) {
                showErrorSnack(context, context.l('Could not accept request'));
              }
            }
          },
          icon: const Icon(Icons.check_rounded, size: 16),
          label: Text(context.l('Accept')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.fernGreenDark,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        TextButton.icon(
          onPressed: () async {
            try {
              await service.rejectFollowRequest(item);
              if (context.mounted) {
                showInfoSnack(context, context.l('Request ignored'));
              }
            } catch (_) {
              if (context.mounted) {
                showErrorSnack(context, context.l('Could not update request'));
              }
            }
          },
          icon: const Icon(Icons.close_rounded, size: 16),
          label: Text(context.l('Ignore')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ],
    );
  }
}

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      'echo_verified' => (Icons.verified_outlined, AppColors.fernGreen),
      'trust_update' => (Icons.trending_up_outlined, AppColors.fernGreen),
      'report_resolved' => (Icons.shield_outlined, AppColors.charcoal),
      'echo_moderation' => (Icons.shield_outlined, AppColors.sunsetCoral),
      'subscription_update' => (
          Icons.workspace_premium_outlined,
          AppColors.fernGreen
        ),
      'bond_settled' => (Icons.link_outlined, AppColors.fernGreen),
      'bond_contested' => (Icons.link_off_outlined, AppColors.sunsetCoral),
      'content_removed' => (
          Icons.delete_outline_rounded,
          AppColors.sunsetCoral
        ),
      'identity_verified' => (Icons.verified_user_rounded, AppColors.fernGreen),
      'follow_request' => (Icons.person_add_alt_1_rounded, AppColors.fernGreen),
      'follow_request_accepted' => (
          Icons.how_to_reg_rounded,
          AppColors.fernGreen
        ),
      'new_follower' => (Icons.group_add_rounded, AppColors.fernGreen),
      'new_follower_echo' => (Icons.dynamic_feed_outlined, AppColors.fernGreen),
      'echo_supported' => (Icons.thumb_up_alt_outlined, AppColors.fernGreen),
      'echo_challenged' => (
          Icons.report_problem_outlined,
          AppColors.sunsetCoral
        ),
      'context_like' => (Icons.favorite_border_rounded, AppColors.fernGreen),
      'echo_reply' => (Icons.reply_outlined, AppColors.fernGreen),
      'reply_reply' => (Icons.forum_outlined, AppColors.fernGreen),
      'reply_like' => (Icons.favorite_outline_rounded, AppColors.fernGreen),
      _ => (Icons.notifications_outlined, AppColors.textTertiary),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}
