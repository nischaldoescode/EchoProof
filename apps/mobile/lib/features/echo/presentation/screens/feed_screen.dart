// feed screen — main home screen
// shows ranked echo feed with animated card entrances
// supports pull-to-refresh, infinite scroll pagination
// fully responsive: 1-col phone, 2-col tablet

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../providers/echo_feed_provider.dart';
import '../widgets/echo_card.dart';
import '../../../../shared/widgets/shimmer_loader.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      ref.read(echoFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(echoFeedProvider);
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 700;

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: _FeedAppBar(),
      floatingActionButton: _CreateEchoFab(),
      body: feedAsync.when(
        loading: () => const _FeedShimmer(),
        error: (e, _) =>
            _ErrorState(onRetry: () => ref.refresh(echoFeedProvider)),
        data: (feed) {
          if (feed.echoes.isEmpty) return const _EmptyFeed();

          if (isTablet) {
            return _TabletGrid(
              echoes: feed.echoes,
              isLoadingMore: feed.isLoadingMore,
              scrollController: _scrollController,
              hasMore: feed.hasMore,
            );
          }

          return RefreshIndicator(
            color: AppColors.fernGreen,
            onRefresh: () => ref.read(echoFeedProvider.notifier).refresh(),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 120),
              itemCount: feed.echoes.length + (feed.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == feed.echoes.length) {
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.fernGreen),
                      ),
                    ),
                  );
                }
                return _AnimatedEchoCard(
                  key: ValueKey(feed.echoes[index].id),
                  echo: feed.echoes[index],
                  index: index,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// staggered 3d entrance animation for each echo card
class _AnimatedEchoCard extends StatefulWidget {
  const _AnimatedEchoCard({
    super.key,
    required this.echo,
    required this.index,
  });

  final EchoEntity echo;
  final int index;

  @override
  State<_AnimatedEchoCard> createState() => _AnimatedEchoCardState();
}

class _AnimatedEchoCardState extends State<_AnimatedEchoCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  late final Animation<double> _rotX; // 3d flip-up entrance

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // stagger based on index — first 8 cards animate, rest appear instantly
    final delay = widget.index < 8
        ? Duration(milliseconds: widget.index * 60)
        : Duration.zero;

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _translateY = Tween<double>(begin: 24, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _rotX = Tween<double>(begin: 0.08, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(_rotX.value)
              ..translate(0.0, _translateY.value),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
      child: EchoCard(
        echo: widget.echo,
        onTap: () => context.push('/feed/echo/${widget.echo.id}'),
      ),
    );
  }
}

/// two-column grid layout for tablets
class _TabletGrid extends StatelessWidget {
  const _TabletGrid({
    required this.echoes,
    required this.isLoadingMore,
    required this.scrollController,
    required this.hasMore,
  });

  final List<EchoEntity> echoes;
  final bool isLoadingMore;
  final ScrollController scrollController;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.85,
      ),
      itemCount: echoes.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == echoes.length) {
          return const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.fernGreen),
          );
        }
        return _AnimatedEchoCard(
          key: ValueKey(echoes[index].id),
          echo: echoes[index],
          index: index,
        );
      },
    );
  }
}

class _FeedAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/images/logo.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('Echoproof', style: AppTypography.textTheme.titleLarge),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_none_outlined, size: 22),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.person_outline, size: 22),
          onPressed: () {},
        ),
      ],
    );
  }
}

class _MiniWavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.fernGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    for (int i = 1; i <= 2; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: i * 5.0),
        -0.6,
        3.5,
        false,
        paint,
      );
    }
    canvas.drawCircle(Offset(cx, cy), 1.5, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CreateEchoFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => context.push('/create'),
      backgroundColor: AppColors.charcoal,
      foregroundColor: AppColors.white,
      elevation: 2,
      icon: const Icon(Icons.add, size: 20),
      label: Text(
        'Create Echo',
        style: AppTypography.textTheme.labelLarge
            ?.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _FeedShimmer extends StatelessWidget {
  const _FeedShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: EchoCardShimmer(),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.softSand,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.wb_sunny_outlined,
                  size: 36, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Nothing yet', style: AppTypography.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Be the first to create an echo in your communities.',
              style: AppTypography.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.borderSubtle, width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (i) {
          if (i == 0) context.go('/feed');
          if (i == 1) context.go('/discover');
          if (i == 2) context.go('/feed'); // profile — wire to /profile
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppSpacing.lg),
          Text('Could not load feed',
              style: AppTypography.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
