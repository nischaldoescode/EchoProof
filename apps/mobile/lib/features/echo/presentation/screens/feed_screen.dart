import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
<<<<<<< HEAD
=======
import '../../domain/entities/feed_filter.dart';
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
import '../services/echo_feed_service.dart';
import '../widgets/echo_card.dart';
import '../widgets/feed_filter_sheet.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
<<<<<<< HEAD
=======
import 'package:echoproof/shared/widgets/app_bottom_nav.dart';
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
import '../../../../app/app.dart';
import '../../../../shared/widgets/ad_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

int _computeItemCount(EchoFeedService feed) {
  final echoCount = feed.echoes.length;

  // one ad every 7 echoes
  final adCount = echoCount ~/ 7;

  // +1 for loading spinner if more data exists
  return echoCount + adCount + (feed.hasMore ? 1 : 0);
}

class _FeedScreenState extends State<FeedScreen> {
  final _scrollCtrl = ScrollController();
  FeedFilter _filter = const FeedFilter();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feed = context.read<EchoFeedService>();
      if (feed.echoes.isEmpty) feed.loadFeed();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 400) {
      context.read<EchoFeedService>().loadMore();
    }
  }

  Future<void> _openFilter() async {
    HapticFeedback.lightImpact();
    final result = await showFeedFilterSheet(context, _filter);
    if (result != null) {
      setState(() => _filter = result);
    }
  }

  List<EchoEntity> _filtered(List<EchoEntity> echoes) {
    return _filter.apply(echoes);
  }

  int _itemCount(List<EchoEntity> filtered, bool hasMore) {
    final adCount = filtered.length ~/ 7;
    return filtered.length + adCount + (hasMore ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<EchoFeedService>();
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 700;

<<<<<<< HEAD
    return ExitConfirmWrapper(
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: _FeedAppBar(),
        floatingActionButton: _CreateEchoFab(),
        bottomNavigationBar: _BottomNav(currentIndex: 0),
        body: _buildBody(feed, isTablet),
      ),
    );
=======
    return SwipeNavigationWrapper(
        currentLocation: '/feed',
        child: ExitConfirmWrapper(
          child: Scaffold(
            backgroundColor: AppColors.white,
            appBar: _FeedAppBar(
              filterActive: _filter.isActive,
              onFilterTap: _openFilter,
            ),
            floatingActionButton: const _CreateFab(),
            bottomNavigationBar: const AppBottomNav(currentLocation: '/feed'),
            body: _buildBody(feed, isTablet),
          ),
        ));
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
  }

  Widget _buildBody(EchoFeedService feed, bool isTablet) {
    if (feed.isLoading && feed.echoes.isEmpty) return const _Shimmer();

    if (feed.loadState == FeedLoadState.error && feed.echoes.isEmpty) {
      return _ErrorState(
        onRetry: () => context.read<EchoFeedService>().loadFeed(),
      );
    }

    final filtered = _filtered(feed.echoes);

    if (feed.echoes.isEmpty) return const _EmptyFeed();

    if (filtered.isEmpty && _filter.isActive) {
      return _EmptyFilter(
          onClear: () => setState(() => _filter = const FeedFilter()));
    }

<<<<<<< HEAD
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
      onRefresh: () => context.read<EchoFeedService>().refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 120),
        itemCount: _computeItemCount(feed),
        itemBuilder: (context, index) {
          // show ad card every 7th slot (index 6, 13, 20...)
          if (index > 0 && index % 7 == 6) {
            return const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: AdCard(),
            );
          }

          final adsBefore = index ~/ 7;
          final echoIndex = index - adsBefore;

          // loader at end
          if (echoIndex >= feed.echoes.length) {
            return const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.fernGreen,
                  ),
=======
    return Column(
      children: [
        if (_filter.isActive)
          _ActiveFilterBar(
            filter: _filter,
            onClear: () => setState(() => _filter = const FeedFilter()),
            onTap: _openFilter,
          ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.fernGreen,
            onRefresh: () => context.read<EchoFeedService>().refresh(),
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 120),
              itemCount: _itemCount(filtered, feed.hasMore),
              itemBuilder: (ctx, index) {
                if (index > 0 && index % 7 == 6) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AdCard(),
                  );
                }

                final adsBefore = index ~/ 7;
                final echoIndex = index - adsBefore;

                if (echoIndex >= filtered.length) {
                  if (!feed.hasMore) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.fernGreen,
                        ),
                      ),
                    ),
                  );
                }

                return _AnimatedCard(
                  key: ValueKey(filtered[echoIndex].id),
                  echo: filtered[echoIndex],
                  index: echoIndex,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveFilterBar extends StatelessWidget {
  const _ActiveFilterBar({
    required this.filter,
    required this.onClear,
    required this.onTap,
  });

  final FeedFilter filter;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (filter.showVerifiedOnly) parts.add('Verified only');
    if (filter.showUnverifiedOnly) parts.add('Unverified only');
    if (filter.statuses.isNotEmpty)
      parts.add('${filter.statuses.length} status');
    if (filter.categories.isNotEmpty)
      parts.add('${filter.categories.length} categories');
    if (filter.sortBy != FeedSortBy.trending) parts.add(filter.sortBy.label);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        color: AppColors.charcoal.withValues(alpha: 0.04),
        child: Row(
          children: [
            const Icon(Icons.tune_rounded, size: 14, color: AppColors.charcoal),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                parts.join(' · '),
                style: GoogleFonts.josefinSans(
                  fontSize: 12,
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w500,
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
                ),
                overflow: TextOverflow.ellipsis,
              ),
<<<<<<< HEAD
            );
          }

          return _AnimatedEchoCard(
            key: ValueKey(feed.echoes[echoIndex].id),
            echo: feed.echoes[echoIndex],
            index: echoIndex,
          );
        },
=======
            ),
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close_rounded,
                  size: 16, color: AppColors.textTertiary),
            ),
          ],
        ),
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
      ),
    );
  }
}

class _AnimatedCard extends StatefulWidget {
  const _AnimatedCard({super.key, required this.echo, required this.index});
  final EchoEntity echo;
  final int index;

  @override
  State<_AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<_AnimatedCard>
    with SingleTickerProviderStateMixin {
<<<<<<< HEAD
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _translateY;
  late final Animation<double> _rotX;
=======
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<double> _y;
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    _y = Tween<double>(begin: 16, end: 0).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
    );

    final delay = widget.index < 8
        ? Duration(milliseconds: widget.index * 45)
        : Duration.zero;
    Future.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
<<<<<<< HEAD
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(_rotX.value)
              ..translateByDouble(0.0, _translateY.value, 0.0, 1.0),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
=======
      animation: _c,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: Offset(0, _y.value),
          child: child,
        ),
      ),
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
      child: EchoCard(
        echo: widget.echo,
        onTap: () => context.push('/feed/echo/${widget.echo.id}'),
      ),
    );
  }
}

class _FeedAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _FeedAppBar({
    required this.filterActive,
    required this.onFilterTap,
  });

<<<<<<< HEAD
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
        // ads every 7 items
        if (index > 0 && index % 7 == 6) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: AdCard(),
          );
        }

        final adsBefore = index ~/ 7;
        final echoIndex = index - adsBefore;

        if (echoIndex >= echoes.length) {
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.fernGreen,
            ),
          );
        }

        return _AnimatedEchoCard(
          key: ValueKey(echoes[echoIndex].id),
          echo: echoes[echoIndex],
          index: echoIndex,
        );
      },
    );
  }
}

class _FeedAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
=======
  final bool filterActive;
  final VoidCallback onFilterTap;

  @override
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: AppColors.borderSubtle,
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
          const SizedBox(width: 8),
          Text('Echoproof', style: AppTypography.textTheme.titleLarge),
        ],
      ),
      actions: [
        // filter button with active indicator
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 22),
              onPressed: onFilterTap,
              color: filterActive ? AppColors.charcoal : AppColors.charcoal,
              tooltip: 'Filter',
            ),
            if (filterActive)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.fernGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded, size: 22),
          onPressed: () => context.push('/search'),
          color: AppColors.charcoal,
          tooltip: 'Search',
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _CreateFab extends StatefulWidget {
  const _CreateFab();

  @override
<<<<<<< HEAD
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => context.push('/create'),
      backgroundColor: AppColors.charcoal,
      foregroundColor: AppColors.white,
      elevation: 2,
      icon: const Icon(Icons.add, size: 20),
      label: Text(
        'Create Echo',
        style: AppTypography.textTheme.labelLarge?.copyWith(
          color: AppColors.white,
        ),
      ),
    );
  }
=======
  State<_CreateFab> createState() => _CreateFabState();
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
}

class _CreateFabState extends State<_CreateFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _c.forward(),
        onTapUp: (_) async {
          await _c.reverse();
          if (context.mounted) context.push('/create');
        },
<<<<<<< HEAD
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
=======
        onTapCancel: () => _c.reverse(),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.charcoal,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
        ),
>>>>>>> 9ac05ed (removed secrets + cleanup and added new features)
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      itemCount: 6,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
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
              'Be the first to create an echo.',
              style: AppTypography.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  const _EmptyFilter({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.filter_alt_off_outlined,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.lg),
            Text('No echoes match your filters',
                style: AppTypography.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Try adjusting or clearing your filters.',
              style: AppTypography.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onClear,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.charcoal,
                side: const BorderSide(color: AppColors.charcoal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Clear filters',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
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
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.charcoal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('Try again',
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
