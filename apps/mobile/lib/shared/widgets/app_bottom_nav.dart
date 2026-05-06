import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app/theme/colors.dart';

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
    if (location.startsWith('/profile')) return '/profile';
    return '/feed';
  }

  @override
  Widget build(BuildContext context) {
    final activePath = _activePathFor(currentLocation);

    return Container(
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
                        child: AnimatedSwitcher(
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
                      ),
                      const SizedBox(height: 2),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: GoogleFonts.josefinSans(
                          fontSize: 10,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w400,
                          color: isActive
                              ? AppColors.charcoal
                              : AppColors.textTertiary,
                        ),
                        child: Text(item.label),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
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
    with SingleTickerProviderStateMixin {
  static const _routes = ['/feed', '/discover', '/profile'];

  late final AnimationController _swipeCtrl;
  late Animation<double> _perspectiveAnim;
  late Animation<double> _translateAnim;
  late Animation<double> _opacityAnim;

  double _dragStartX = 0;
  bool _isDragging = false;
  int _swipeDirection = 0;

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _perspectiveAnim = Tween<double>(begin: 0, end: 0).animate(_swipeCtrl);
    _translateAnim = Tween<double>(begin: 0, end: 0).animate(_swipeCtrl);
    _opacityAnim = Tween<double>(begin: 1, end: 1).animate(_swipeCtrl);
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    super.dispose();
  }

  void _setupAnimations(int direction) {
    // direction: -1 = swipe left (go forward), 1 = swipe right (go back)
    _perspectiveAnim = Tween<double>(
      begin: 0,
      end: direction * 0.003,
    ).animate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeInCubic));

    _translateAnim = Tween<double>(
      begin: 0,
      end: direction * -60.0,
    ).animate(CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeInCubic));

    _opacityAnim = Tween<double>(
      begin: 1,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _swipeCtrl,
      curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
    ));
  }

  Future<void> _navigateTo(String route, int direction) async {
    _swipeDirection = direction;
    _setupAnimations(direction);
    await _swipeCtrl.forward();
    if (mounted) {
      context.go(route);
      await Future.delayed(const Duration(milliseconds: 16));
      _swipeCtrl.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _routes.indexOf(widget.currentLocation);

    return GestureDetector(
      onHorizontalDragStart: (details) {
        _dragStartX = details.globalPosition.dx;
        _isDragging = true;
      },
      onHorizontalDragEnd: (details) {
        if (!_isDragging || idx == -1) return;
        _isDragging = false;

        if (details.primaryVelocity == null) return;

        if (details.primaryVelocity! < -400 && idx < _routes.length - 1) {
          _navigateTo(_routes[idx + 1], -1);
        } else if (details.primaryVelocity! > 400 && idx > 0) {
          _navigateTo(_routes[idx - 1], 1);
        }
      },
      child: AnimatedBuilder(
        animation: _swipeCtrl,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnim.value,
            child: Transform(
              alignment: _swipeDirection < 0
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_perspectiveAnim.value)
                ..translateByDouble(_translateAnim.value, 0, 0, 1),
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
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
