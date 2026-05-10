import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';
import 'bottom_ad_banner.dart';
import 'app_banner_ad.dart';
import 'package:provider/provider.dart';
import '../../features/notifications/presentation/services/notification_service.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentLocation});

  final String currentLocation;

  static const _items = [
    _NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Feed',
      path: '/feed',
    ),
    _NavItem(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
      label: 'Discover',
      path: '/discover',
    ),
    _NavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications_rounded,
      label: 'Alerts',
      path: '/notifications',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
      path: '/profile',
    ),
  ];

  String _activePathFor(String location) {
    if (location.startsWith('/feed')) return '/feed';
    if (location.startsWith('/discover')) return '/discover';
    if (location.startsWith('/search')) return '/discover';
    if (location.startsWith('/notifications')) return '/notifications';
    if (location.startsWith('/profile')) return '/profile';
    return '/feed';
  }

  @override
  Widget build(BuildContext context) {
    final activePath = _activePathFor(currentLocation);

    return Column(mainAxisSize: MainAxisSize.min, children: [
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
            height: 60,
            child: Row(
              children: _items.map((item) {
                final isActive = activePath == item.path;
                return Expanded(
                    child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!isActive) {
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
                                  if (count == 0)
                                    return const SizedBox.shrink();
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
      const SizedBox(
        width: double.infinity,
        child: AppBannerAd(),
      ),
    ]);
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
  static const _routes = ['/feed', '/discover', '/notifications', '/profile'];

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

  int get _idx => _routes.indexOf(widget.currentLocation);

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
    // Clamp based on available routes.
    if (delta > 0 && _idx <= 0) delta = 0;
    // On last screen, allow tiny right-swipe drag with rubber-band resistance
    if (delta < 0 && _idx >= _routes.length - 1) {
      delta = delta * 0.12; // rubber-band: 12% resistance
    }
    // On first screen, same for left-swipe
    if (delta > 0 && _idx <= 0) {
      delta = delta * 0.12;
    }
    setState(() => _drag = delta.clamp(-1.0, 1.0));
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
    // Subtle perspective — too much causes a visible gap at the edge.
    m.setEntry(3, 2, 0.0005);
    // Max ~22° rotation — enough to feel 3D without exposing background.
    final angle = p * (3.14159 / 8.0);
    m.rotateY(-angle);
    // Scale down slightly as it rotates — card recedes into space.
    final scale = 1.0 - p.abs() * 0.08;
    m.scaleByDouble(scale, scale, 1.0, 1.0);

    return m;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _exitCtrl,
      builder: (context, _) {
        final p = _exiting ? _exitDirection * _exitProgress.value : _drag;

        final align = p >= 0 ? Alignment.centerLeft : Alignment.centerRight;

        return GestureDetector(
          onHorizontalDragStart: _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd: _onDragEnd,
          // ColoredBox fills the window with app background — prevents
          // the Android black window from showing through the 3D gap.
          child: ColoredBox(
            color: const Color(0xFFF5FAF7), // AppColors.softGreen background
            child: Transform(
              alignment: align,
              transform: _buildMatrix(p),
              child: Opacity(
                // Very subtle opacity — just enough to signal transition.
                opacity: (1.0 - p.abs() * 0.08).clamp(0.0, 1.0),
                child: widget.child,
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
    required this.label,
    required this.path,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
}
