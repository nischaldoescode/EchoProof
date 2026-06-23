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

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
                0,
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
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(minHeight: 58),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 2,
                              vertical: 3,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
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
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
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
            const AppBannerAd(),
          ],
        ),
      ),
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
    with TickerProviderStateMixin {
  static const _routes = [
    '/feed',
    '/discover',
    '/rooms',
    '/notifications',
    '/profile',
  ];

  static String? _pendingEntryRoute;
  static int _pendingEntryDirection = 0;
  static const Curve _rootMotionCurve = Easing.emphasizedDecelerate;

  // drag progress uses positive for previous tab and negative for next tab.
  // this wrapper only moves root destinations, so it must stay cheap enough
  // for dense feed/profile pages and for split-screen resize events.
  double _drag = 0.0;
  bool _dragging = false;
  double _dragStartX = 0.0;

  // controllers are lazy so hot reload cannot leave a newly added field in an
  // uninitialized late state. root swipes use only a small gesture preview:
  // full-screen outgoing slides make dense pages look like the old route is
  // jittering while the next tab is still being prepared.
  AnimationController? _exitCtrl;
  AnimationController? _settleCtrl;
  AnimationController? _entryCtrl;
  Animation<double> _settleProgress = const AlwaysStoppedAnimation(0.0);
  int _entryDirection = 0;
  bool _exiting = false;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _ensureMotionControllers();
    _primeEntryAnimation();
  }

  AnimationController get _exitController {
    return _exitCtrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
  }

  AnimationController get _settleController {
    return _settleCtrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
    );
  }

  AnimationController get _entryController {
    return _entryCtrl ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
  }

  void _ensureMotionControllers() {
    _exitController;
    _settleController;
    _entryController;
  }

  void _primeEntryAnimation() {
    if (_pendingEntryRoute != widget.currentLocation) {
      _pendingEntryRoute = null;
      _pendingEntryDirection = 0;
      _entryDirection = 0;
      _entryController.value = 1;
      return;
    }

    _entryDirection = _pendingEntryDirection;
    _pendingEntryRoute = null;
    _pendingEntryDirection = 0;
    _entryController.value = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entryController.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant SwipeNavigationWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation == widget.currentLocation) return;

    _ensureMotionControllers();
    _settleController.stop();
    _entryController.stop();
    _dragging = false;
    _settling = false;
    _drag = 0.0;
    _primeEntryAnimation();
  }

  @override
  void dispose() {
    _exitCtrl?.dispose();
    _settleCtrl?.dispose();
    _entryCtrl?.dispose();
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
    _settleController.stop();
    _entryController.stop();
    _entryController.value = 1;
    _entryDirection = 0;
    _dragStartX = d.globalPosition.dx;
    _dragging = true;
    _settling = false;
    _drag = 0.0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging || _exiting) return;
    final w = MediaQuery.sizeOf(context).width.clamp(1.0, double.infinity);
    var delta = (d.globalPosition.dx - _dragStartX) / w;
    if (delta > 0 && !_canGoBack) delta = 0;
    if (delta < 0 && !_canGoForward) delta = 0;
    final next = delta.clamp(-0.55, 0.55).toDouble();
    if ((next - _drag).abs() < 0.001) return;
    setState(() => _drag = next);
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
        final entryDirection = targetIdx > _idx ? 1 : -1;
        _triggerExit(_routes[targetIdx], entryDirection);
        return;
      }
    }

    _snapBack();
  }

  void _onDragCancel() {
    if (!_dragging || _exiting) return;
    _dragging = false;
    _snapBack();
  }

  void _snapBack() {
    if (_drag.abs() < 0.001) {
      setState(() => _drag = 0.0);
      return;
    }

    _settling = true;
    _settleProgress = Tween<double>(begin: _drag, end: 0.0).animate(
      CurvedAnimation(parent: _settleController, curve: _rootMotionCurve),
    );

    _settleController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _drag = 0.0;
        _settling = false;
      });
    });
  }

  void _triggerExit(String route, int entryDirection) {
    _exiting = true;
    _drag = 0.0;
    _settling = false;
    _pendingEntryRoute = route;
    _pendingEntryDirection = entryDirection;
    _settleController.stop();
    _exitController.stop();
    if (!mounted) return;
    context.go(route);
    if (mounted) {
      setState(() {
        _drag = 0.0;
        _exiting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureMotionControllers();
    return AnimatedBuilder(
      animation: Listenable.merge([
        _exitController,
        _settleController,
        _entryController,
      ]),
      builder: (context, _) {
        final p = _exiting
            ? 0.0
            : _settling
            ? _settleProgress.value
            : _drag;
        final progress = p.abs().clamp(0.0, 1.0).toDouble();
        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        final direction = p == 0 ? 0.0 : p.sign;
        final easedPreview = _rootMotionCurve.transform(progress);
        final rawOffset = direction * easedPreview * 18;
        final snappedOffset =
            (rawOffset * devicePixelRatio).roundToDouble() / devicePixelRatio;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);
        final entryRaw = reduceMotion
            ? 1.0
            : _entryController.value.clamp(0.0, 1.0).toDouble();
        final entryProgress = _rootMotionCurve.transform(entryRaw);
        final entryOffset = _entryDirection * (1 - entryProgress) * 22;
        final snappedEntryOffset =
            (entryOffset * devicePixelRatio).roundToDouble() / devicePixelRatio;
        final entryOpacity = (0.78 + entryProgress * 0.22)
            .clamp(0.0, 1.0)
            .toDouble();
        final entryScale = 0.985 + entryProgress * 0.015;

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: ColoredBox(
            color: const Color(0xFFF5FAF7),
            child: RepaintBoundary(
              child: Opacity(
                opacity: (entryOpacity * (1.0 - progress * 0.025))
                    .clamp(0.0, 1.0)
                    .toDouble(),
                child: Transform.translate(
                  offset: Offset(snappedEntryOffset + snappedOffset, 0),
                  child: Transform.scale(
                    scale: entryScale,
                    child: widget.child,
                  ),
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
