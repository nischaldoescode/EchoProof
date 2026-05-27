import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';
import 'bottom_ad_banner.dart';
import 'app_banner_ad.dart';
import 'package:provider/provider.dart';
import '../../core/localization/app_copy.dart';
import '../../features/notifications/presentation/services/notification_service.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentLocation});

  final String currentLocation;

  static const _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      labelKey: 'nav.feed',
      path: '/feed',
    ),
    _NavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      labelKey: 'nav.discover',
      path: '/discover',
    ),
    _NavItem(
      icon: Icons.lock_outline_rounded,
      activeIcon: Icons.lock_rounded,
      labelKey: 'nav.rooms',
      path: '/rooms',
    ),
    _NavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications_rounded,
      labelKey: 'nav.alerts',
      path: '/notifications',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person_rounded,
      labelKey: 'nav.profile',
      path: '/profile',
    ),
  ];

  String _activePathFor(String location) {
    if (location.startsWith('/feed')) return '/feed';
    if (location.startsWith('/discover')) return '/discover';
    if (location.startsWith('/search')) return '/discover';
    if (location.startsWith('/rooms')) return '/rooms';
    if (location.startsWith('/notifications')) return '/notifications';
    if (location == '/profile') return '/profile';
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Interstitial prompt banner — above nav, dismissible
        const BottomAdBanner(),

        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: AppColors.borderSubtle, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 55,
              child: Row(
                children: _items.map((item) {
                  final isActive = activePath == item.path;
                  return Expanded(
                      child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (currentLocation != item.path) {
                        context.go(item.path);
                      }
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: isActive ? 16 : 0,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.charcoal.withValues(alpha: 0.08)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  isActive ? item.activeIcon : item.icon,
                                  key: ValueKey('${item.path}_$isActive'),
                                  size: 22,
                                  color: isActive
                                      ? AppColors.charcoal
                                      : AppColors.textTertiary,
                                ),
                              ),
                              // Unread badge for notifications tab.
                              if (item.path == '/notifications')
                                Consumer<NotificationService>(
                                  builder: (_, notif, __) {
                                    final count = notif.unreadCount;
                                    if (count == 0) {
                                      return const SizedBox.shrink();
                                    }
                                    return Positioned(
                                      top: -4,
                                      right: -6,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: AppColors.sunsetCoral,
                                          shape: BoxShape.circle,
                                        ),
                                        constraints: const BoxConstraints(
                                            minWidth: 14, minHeight: 14),
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
                        )
                      ],
                    ),
                  ));
                }).toList(),
              ),
            ),
          ),
        ),
        // const SizedBox(
        //   width: double.infinity,
        //   child: AppBannerAd(),
        // ),
        const SizedBox(height: 5),
        const AppBannerAd(),
      ]),
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

  // Live drag progress: -1.0 (going right→left) to +1.0 (going left→right)
  double _drag = 0.0;
  bool _dragging = false;
  double _dragStartX = 0.0;

  // Exit animation state
  late final AnimationController _exitCtrl;
  late Animation<double> _exitProgress;
  int _exitDirection = 0; // -1 or +1
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
      final dir = _drag > 0 ? 1 : -1; // +1=going back, -1=going forward
      final targetIdx = _idx - dir;
      if (targetIdx >= 0 && targetIdx < _routes.length) {
        _triggerExit(dir, _routes[targetIdx]);
        return;
      }
    }

    // Snap back with spring.
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

  Matrix4 _buildMatrix(double p) {
    if (p == 0.0) return Matrix4.identity();

    final m = Matrix4.identity();
    m.setEntry(3, 2, 0.0014);
    final angle = p * (3.14159 / 3.4);
    m.translateByDouble(p * MediaQuery.sizeOf(context).width * 0.08, 0, 0, 1);
    m.rotateY(-angle);
    final scale = 1.0 - p.abs() * 0.10;
    m.scaleByDouble(scale, scale, 1.0, 1.0);

    return m;
  }

  Matrix4 _buildPreviewMatrix(double p) {
    final m = Matrix4.identity();
    final abs = p.abs().clamp(0.0, 1.0).toDouble();
    final direction = p.sign;
    m.setEntry(3, 2, 0.0012);
    m.translateByDouble(-direction * (1 - abs) * 90, 0, -80 + abs * 80, 1);
    m.rotateY(direction * (1 - abs) * (3.14159 / 5.5));
    m.scaleByDouble(0.90 + abs * 0.07, 0.90 + abs * 0.07, 1, 1);
    return m;
  }

  _NavItem? _previewItemFor(double p) {
    if (p < 0 && _canGoForward) {
      return AppBottomNav._items[_idx + 1];
    }
    if (p > 0 && _canGoBack) {
      return AppBottomNav._items[_idx - 1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _exitCtrl,
      builder: (context, _) {
        final p = _exiting ? _exitDirection * _exitProgress.value : _drag;

        final align = p >= 0 ? Alignment.centerLeft : Alignment.centerRight;
        final previewItem = _previewItemFor(p);
        final progress = p.abs().clamp(0.0, 1.0).toDouble();

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          // ColoredBox fills the window with app background — prevents
          // the Android black window from showing through the 3D gap.
          child: ColoredBox(
            color: const Color(0xFFF5FAF7), // AppColors.softGreen background
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (previewItem != null && progress > 0)
                  Opacity(
                    opacity: (progress * 1.35).clamp(0.0, 0.92).toDouble(),
                    child: Transform(
                      alignment:
                          p < 0 ? Alignment.centerRight : Alignment.centerLeft,
                      transform: _buildPreviewMatrix(p),
                      child: _RoutePreviewCard(item: previewItem),
                    ),
                  ),
                Transform(
                  alignment: align,
                  transform: _buildMatrix(p),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: progress == 0
                          ? const []
                          : [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.10 * progress),
                                blurRadius: 30 * progress,
                                offset: Offset(0, 12 * progress),
                              ),
                            ],
                    ),
                    child: Opacity(
                      opacity:
                          (1.0 - progress * 0.08).clamp(0.0, 1.0).toDouble(),
                      child: widget.child,
                    ),
                  ),
                ),
              ],
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
    required this.labelKey,
    required this.path,
  });

  final IconData icon;
  final IconData activeIcon;
  final String labelKey;
  final String path;
}

class _RoutePreviewCard extends StatelessWidget {
  const _RoutePreviewCard({required this.item});

  final _NavItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 62, 22, 96),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.activeIcon, color: AppColors.fernGreen, size: 34),
              const SizedBox(height: 10),
              Text(
                context.tx(item.labelKey),
                style: GoogleFonts.josefinSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
