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

class SwipeNavigationWrapper extends StatelessWidget {
  const SwipeNavigationWrapper({
    super.key,
    required this.currentLocation,
    required this.child,
  });

  final String currentLocation;
  final Widget child;

  static const _routes = ['/feed', '/discover', '/profile'];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final idx = _routes.indexOf(currentLocation);
        if (idx == -1) return; // not a root tab — no swipe
        
        if (details.primaryVelocity == null) return;
        
        if (details.primaryVelocity! < -300 && idx < _routes.length - 1) {
          // swipe left → next tab
          context.go(_routes[idx + 1]);
        } else if (details.primaryVelocity! > 300 && idx > 0) {
          // swipe right → previous tab
          context.go(_routes[idx - 1]);
        }
      },
      child: child,
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