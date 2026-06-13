// app bottom navigation
// @params currentlocation selects the active root destination

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/theme/colors.dart';
import '../../app/theme/spacing.dart';
import '../../features/echo/presentation/services/echo_feed_service.dart';
import '../../features/notifications/presentation/services/notification_service.dart';
import 'app_banner_ad.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentLocation,
    this.onFeedTap,
  });

  final String currentLocation;
  final FutureOr<void> Function()? onFeedTap;

  static const _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      path: '/feed',
      label: 'Home',
    ),
    _NavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      path: '/discover',
      label: 'Explore',
    ),
    _NavItem(
      icon: Icons.lock_outline_rounded,
      activeIcon: Icons.lock_rounded,
      path: '/rooms',
      label: 'Rooms',
    ),
    _NavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications_rounded,
      path: '/notifications',
      label: 'Activity',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person_rounded,
      path: '/profile',
      label: 'Profile',
    ),
  ];

  String _activePathFor(String location) {
    if (location.startsWith('/feed')) return '/feed';
    if (location.startsWith('/discover')) return '/discover';
    if (location.startsWith('/search')) return '/discover';
    if (location.startsWith('/rooms')) return '/rooms';
    if (location.startsWith('/notifications')) return '/notifications';
    if (location == '/profile') return '/profile';
    if (location.startsWith('/profile/analytics')) return '/profile';
    if (location.startsWith('/profile/')) return '/feed';
    return '/feed';
  }

  @override
  Widget build(BuildContext context) {
    final activePath = _activePathFor(currentLocation);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFDFDFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.charcoal.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SizedBox(
                height: 64,
                child: Row(
                  children: _items.map((item) {
                    final isActive = activePath == item.path;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (item.path == '/feed') {
                            if (activePath == '/feed' && onFeedTap != null) {
                              unawaited(Future<void>.sync(onFeedTap!));
                              return;
                            }
                            final notifications = context
                                .read<NotificationService>();
                            unawaited(
                              context.read<EchoFeedService>().refresh().then(
                                (_) => notifications.markFollowerEchoesRead(),
                              ),
                            );
                          }
                          if (currentLocation != item.path) {
                            context.go(item.path);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.charcoal.withValues(alpha: 0.9)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 180),
                                    child: Icon(
                                      isActive ? item.activeIcon : item.icon,
                                      key: ValueKey('${item.path}_$isActive'),
                                      size: 21,
                                      color: isActive
                                          ? Colors.white
                                          : AppColors.charcoal.withValues(
                                              alpha: 0.68,
                                            ),
                                    ),
                                  ),
                                  // unread dot for followed user posts
                                  if (item.path == '/feed')
                                    Consumer<NotificationService>(
                                      builder: (context, notif, child) {
                                        if (!notif.hasUnreadFollowerEcho) {
                                          return const SizedBox.shrink();
                                        }
                                        return Positioned(
                                          top: -4,
                                          right: -7,
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: AppColors.fernGreen,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: isActive
                                                    ? AppColors.charcoal
                                                    : Colors.white,
                                                width: 1.4,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  // unread badge for notifications tab
                                  if (item.path == '/notifications')
                                    Consumer<NotificationService>(
                                      builder: (context, notif, child) {
                                        final count = notif.unreadCount;
                                        if (count == 0) {
                                          return const SizedBox.shrink();
                                        }
                                        return Positioned(
                                          top: -6,
                                          right: -9,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: const BoxDecoration(
                                              color: AppColors.sunsetCoral,
                                              shape: BoxShape.circle,
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 14,
                                              minHeight: 14,
                                            ),
                                            child: Text(
                                              count > 9 ? '9+' : '$count',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                  color: isActive
                                      ? Colors.white
                                      : AppColors.textSecondary,
                                  letterSpacing: 0,
                                ),
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const AppBannerAd(),
      ],
    );
  }
}

class SwipeNavigationWrapper extends StatefulWidget {
  const SwipeNavigationWrapper({
    super.key,
    required this.currentLocation,
    required this.child,
  });

  final String currentLocation;
  final Widget child;

  @override
  State<SwipeNavigationWrapper> createState() => _SwipeNavigationWrapperState();
}

class _SwipeNavigationWrapperState extends State<SwipeNavigationWrapper>
    with SingleTickerProviderStateMixin {
  static const _routes = [
    '/feed',
    '/discover',
    '/rooms',
    '/notifications',
    '/profile',
  ];

  // drag progress uses positive for previous tab and negative for next tab
  double _drag = 0.0;
  bool _dragging = false;
  double _dragStartX = 0.0;

  // exit animation finishes the slide before routing
  late final AnimationController _exitCtrl;
  late Animation<double> _exitProgress;
  int _exitDirection = 0;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _exitProgress = const AlwaysStoppedAnimation(0.0);
  }

  @override
  void dispose() {
    _exitCtrl.dispose();
    super.dispose();
  }

  int get _idx {
    final index = _routes.indexOf(widget.currentLocation);
    return index < 0 ? 0 : index;
  }

  bool get _canGoBack => _idx > 0;
  bool get _canGoForward => _idx < _routes.length - 1;

  void _onDragStart(DragStartDetails d) {
    if (_exiting) return;
    _dragStartX = d.globalPosition.dx;
    _dragging = true;
    _drag = 0.0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging || _exiting) return;
    final w = MediaQuery.sizeOf(context).width;
    var delta = (d.globalPosition.dx - _dragStartX) / w;
    if (delta > 0 && !_canGoBack) delta = 0;
    if (delta < 0 && !_canGoForward) delta = 0;
    setState(() => _drag = delta.clamp(-1.0, 1.0).toDouble());
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_dragging || _exiting) return;
    _dragging = false;

    final velocity = d.primaryVelocity ?? 0;
    final shouldNavigate = _drag.abs() > 0.3 || velocity.abs() > 500;

    if (shouldNavigate && _drag != 0) {
      final dir = _drag > 0 ? 1 : -1;
      final targetIdx = _idx - dir;
      if (targetIdx >= 0 && targetIdx < _routes.length) {
        _triggerExit(dir, _routes[targetIdx]);
        return;
      }
    }

    _snapBack();
  }

  void _snapBack() {
    setState(() => _drag = 0.0);
  }

  Future<void> _triggerExit(int dir, String route) async {
    _exiting = true;
    _exitDirection = dir;
    _exitProgress = Tween<double>(
      begin: _drag.abs(),
      end: 1.0,
    ).animate(CurvedAnimation(parent: _exitCtrl, curve: Curves.easeInCubic));

    await _exitCtrl.forward(from: 0);
    if (!mounted) return;
    context.go(route);
    await Future.microtask(() {});
    if (mounted) {
      _exitCtrl.reset();
      setState(() {
        _drag = 0.0;
        _exiting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _exitCtrl,
      builder: (context, _) {
        final p = _exiting ? _exitDirection * _exitProgress.value : _drag;
        final width = MediaQuery.sizeOf(context).width;
        final progress = p.abs().clamp(0.0, 1.0).toDouble();

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          child: ColoredBox(
            color: const Color(0xFFF5FAF7),
            child: Transform.translate(
              offset: Offset(p * width, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: progress == 0
                      ? const []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.07 * progress,
                            ),
                            blurRadius: 22 * progress,
                            offset: Offset(0, 8 * progress),
                          ),
                        ],
                ),
                child: Opacity(
                  opacity: (1.0 - progress * 0.04).clamp(0.0, 1.0).toDouble(),
                  child: widget.child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.path,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String path;
  final String label;
}
