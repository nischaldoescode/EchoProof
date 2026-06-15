// notifications screen
// shows notification history, marks all as read on open
// uses notificationservice via provider no riverpod

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
import '../../../../core/services/account_device_service.dart';

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
          bottomNavigationBar: const AppBottomNav(
            currentLocation: '/notifications',
          ),
          body: _NotificationsBody(service: service, timeAgo: _timeAgo),
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

class _NotificationsBody extends StatelessWidget {
  const _NotificationsBody({required this.service, required this.timeAgo});

  final NotificationService service;
  final String Function(DateTime) timeAgo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.fernGreen,
        onRefresh: service.loadNotifications,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            112,
          ),
          children: [
            _NotificationsHeader(service: service),
            const SizedBox(height: AppSpacing.md),
            if (service.isLoading) ...[
              const SizedBox(height: 140),
              const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.fernGreen,
                ),
              ),
            ] else if (service.notifications.isEmpty) ...[
              const SizedBox(height: 120),
              _EmptyNotifications(),
            ] else ...[
              for (var i = 0; i < service.notifications.length; i++)
                _NotificationCard(
                  item: service.notifications[i],
                  index: i,
                  timeAgo: timeAgo,
                  onTap: () => service.openNotification(
                    context,
                    service.notifications[i],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({required this.service});

  final NotificationService service;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l('Activity'),
                style: AppTypography.textTheme.headlineSmall?.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.l('Follows, replies, records, and account signals'),
                style: AppTypography.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: service.unreadCount == 0 ? null : service.markAllRead,
          icon: const Icon(Icons.done_all_rounded, size: 17),
          label: Text(context.l('Read all')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.fernGreenDark,
            disabledForegroundColor: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({
    required this.item,
    required this.index,
    required this.timeAgo,
    required this.onTap,
  });

  final NotificationItem item;
  final int index;
  final String Function(DateTime) timeAgo;
  final VoidCallback onTap;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  @override
  Widget build(BuildContext context) {
    final service = context.read<NotificationService>();

    final card = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: _buildCardSurface(),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(
        milliseconds: 260 + (widget.index.clamp(0, 5).toInt() * 35),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Dismissible(
        key: ValueKey('notification_${widget.item.id}'),
        direction: DismissDirection.endToStart,
        resizeDuration: const Duration(milliseconds: 220),
        movementDuration: const Duration(milliseconds: 260),
        dismissThresholds: const {DismissDirection.endToStart: 0.36},
        background: const SizedBox.shrink(),
        secondaryBackground: const _DeleteNotificationBackground(),
        confirmDismiss: (_) async {
          service.beginSwipeDelete(widget.item.id);
          final deleted = await service.deleteNotificationRemote(widget.item);
          if (!deleted && context.mounted) {
            service.cancelSwipeDelete(widget.item.id);
            showErrorSnack(context, context.l('Could not delete notification'));
          }
          return deleted;
        },
        onDismissed: (_) => service.finishSwipeDelete(widget.item),
        child: card,
      ),
    );
  }

  Widget _buildCardSurface() {
    return Material(
      color: widget.item.read
          ? AppColors.white
          : AppColors.fernGreenLight.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.item.read
                  ? AppColors.borderSubtle
                  : AppColors.fernGreen.withValues(alpha: 0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.item.read ? 0.018 : 0.032,
                ),
                blurRadius: widget.item.read ? 10 : 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotificationIcon(type: widget.item.type),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildNotificationText()),
              if (!widget.item.read) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.fernGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationText() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.item.title,
                style: AppTypography.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              widget.timeAgo(widget.item.createdAt),
              style: AppTypography.textTheme.labelMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          widget.item.body,
          style: AppTypography.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (widget.item.type == 'follow_request' &&
            widget.item.data?['handled'] != true) ...[
          const SizedBox(height: AppSpacing.sm),
          _FollowRequestActions(item: widget.item),
        ],
        if (widget.item.type == 'new_follower') ...[
          const SizedBox(height: AppSpacing.sm),
          _NewFollowerActions(item: widget.item),
        ],
        if (widget.item.type == 'account_device_login_attempt') ...[
          const SizedBox(height: AppSpacing.sm),
          _AccountDeviceAlertActions(item: widget.item),
        ],
      ],
    );
  }
}

class _DeleteNotificationBackground extends StatelessWidget {
  const _DeleteNotificationBackground();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.sunsetCoral.withValues(alpha: 0.82),
              AppColors.sunsetCoralDark,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.l('Delete'),
                    style: AppTypography.textTheme.labelMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

class _NewFollowerActions extends StatefulWidget {
  const _NewFollowerActions({required this.item});
  final NotificationItem item;

  @override
  State<_NewFollowerActions> createState() => _NewFollowerActionsState();
}

class _NewFollowerActionsState extends State<_NewFollowerActions> {
  late Future<bool> _isFollowingFuture;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _isFollowingFuture = _loadState();
  }

  @override
  void didUpdateWidget(covariant _NewFollowerActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.data != widget.item.data) {
      _isFollowingFuture = _loadState();
    }
  }

  Future<bool> _loadState() {
    return context.read<NotificationService>().isFollowingActor(widget.item);
  }

  Future<void> _followBack() async {
    if (_isBusy) return;

    setState(() => _isBusy = true);
    try {
      final result = await context.read<NotificationService>().followBack(
        widget.item,
      );
      if (!mounted) return;
      final message = result == 'requested'
          ? 'Follow request sent'
          : 'Followed back';
      showSuccessSnack(context, context.l(message));
      setState(() => _isFollowingFuture = Future.value(true));
    } catch (_) {
      if (mounted) {
        showErrorSnack(context, context.l('Could not follow back'));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.item.data?['follow_back_status'] as String?;
    if (status == 'following') {
      return _NotificationStatusChip(
        icon: Icons.check_rounded,
        label: context.l('Following'),
      );
    }
    if (status == 'requested') {
      return _NotificationStatusChip(
        icon: Icons.schedule_rounded,
        label: context.l('Requested'),
      );
    }

    return FutureBuilder<bool>(
      future: _isFollowingFuture,
      builder: (context, snapshot) {
        final isFollowing = snapshot.data ?? false;
        if (isFollowing) {
          return _NotificationStatusChip(
            icon: Icons.check_rounded,
            label: context.l('Following'),
          );
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _isBusy ? null : _followBack,
            icon: _isBusy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.fernGreen,
                    ),
                  )
                : const Icon(Icons.person_add_alt_1_rounded, size: 16),
            label: Text(context.l('Follow back')),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.fernGreenDark,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        );
      },
    );
  }
}

class _AccountDeviceAlertActions extends StatefulWidget {
  const _AccountDeviceAlertActions({required this.item});
  final NotificationItem item;

  @override
  State<_AccountDeviceAlertActions> createState() =>
      _AccountDeviceAlertActionsState();
}

class _AccountDeviceAlertActionsState
    extends State<_AccountDeviceAlertActions> {
  bool _isBusy = false;

  Future<void> _secureThisDevice() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    final devices = context.read<AccountDeviceService>();
    final notifications = context.read<NotificationService>();
    try {
      await devices.secureThisDevice();
      await notifications.markDeviceAlertHandled(widget.item, 'secured');
      if (!mounted) return;
      showSuccessSnack(context, context.l('Other device logged out'));
    } catch (_) {
      if (mounted) {
        showErrorSnack(context, context.l('Could not secure this account'));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _dismiss() async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      final deleted = await context
          .read<NotificationService>()
          .deleteNotification(widget.item);
      if (!deleted && mounted) {
        showErrorSnack(context, context.l('Could not delete notification'));
      }
    } catch (_) {
      if (mounted) {
        showErrorSnack(context, context.l('Could not delete notification'));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final handled = widget.item.data?['handled'] == true;
    final status = widget.item.data?['status'] as String?;
    if (handled) {
      if (status != 'secured') return const SizedBox.shrink();
      return _NotificationStatusChip(
        icon: Icons.lock_outline_rounded,
        label: context.l('Secured'),
      );
    }

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        TextButton.icon(
          onPressed: _isBusy ? null : _secureThisDevice,
          icon: _isBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.sunsetCoral,
                  ),
                )
              : const Icon(Icons.lock_outline_rounded, size: 16),
          label: Text(context.l('Not you')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.sunsetCoralDark,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
        TextButton.icon(
          onPressed: _isBusy ? null : _dismiss,
          icon: const Icon(Icons.check_rounded, size: 16),
          label: Text(context.l('It was me')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
        ),
      ],
    );
  }
}

class _NotificationStatusChip extends StatelessWidget {
  const _NotificationStatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.textTheme.labelMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
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
      'echo_verified' => (Icons.verified_outlined, AppColors.fernGreen),
      'trust_update' => (Icons.trending_up_outlined, AppColors.fernGreen),
      'report_resolved' => (Icons.shield_outlined, AppColors.charcoal),
      'echo_moderation' => (Icons.shield_outlined, AppColors.sunsetCoral),
      'subscription_update' => (
        Icons.workspace_premium_outlined,
        AppColors.fernGreen,
      ),
      'bond_settled' => (Icons.link_outlined, AppColors.fernGreen),
      'bond_contested' => (Icons.link_off_outlined, AppColors.sunsetCoral),
      'content_removed' => (
        Icons.delete_outline_rounded,
        AppColors.sunsetCoral,
      ),
      'identity_verified' => (Icons.verified_user_rounded, AppColors.fernGreen),
      'follow_request' => (Icons.person_add_alt_1_rounded, AppColors.fernGreen),
      'follow_request_accepted' => (
        Icons.how_to_reg_rounded,
        AppColors.fernGreen,
      ),
      'new_follower' => (Icons.group_add_rounded, AppColors.fernGreen),
      'new_follower_echo' => (Icons.dynamic_feed_outlined, AppColors.fernGreen),
      'account_device_login_attempt' => (
        Icons.phonelink_lock_rounded,
        AppColors.sunsetCoral,
      ),
      'echo_supported' => (Icons.thumb_up_alt_outlined, AppColors.fernGreen),
      'echo_challenged' => (
        Icons.report_problem_outlined,
        AppColors.sunsetCoral,
      ),
      'context_requested' => (
        Icons.fact_check_outlined,
        AppColors.statusUnderReview,
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
