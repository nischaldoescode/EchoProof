// feed screen
// @params none shows the signed-in home feed and root navigation

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/feed_filter.dart';
import '../services/echo_feed_service.dart';
import '../widgets/echo_card.dart';
import '../widgets/feed_filter_sheet.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import 'package:echoproof/shared/widgets/app_bottom_nav.dart';
import '../../../../app/app.dart';
import '../../../../shared/widgets/rating_prompt.dart';
import '../../../auth/presentation/screens/permission_sheet.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/create_echo_service.dart';
import '../../../../shared/widgets/birthday_celebration.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/storage_keys.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../core/services/ad_service.dart';
import '../../../subscription/presentation/services/subscription_service.dart';
import '../../../../core/utils/snack.dart';
import '../../../notifications/presentation/services/notification_service.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  FeedFilter _filter = const FeedFilter();
  Timer? _feedAdTimer;
  DateTime _lastActiveAt = DateTime.now();

  Future<void> _maybeTriggerBirthdayEaster() async {
    // check once per app session using hive
    final box = Hive.box('app_settings');
    final today = DateTime.now();
    final lastChecked =
        box.get('birthday_checked_date', defaultValue: '') as String;
    final todayStr = '${today.year}-${today.month}-${today.day}';
    if (lastChecked == todayStr) return;
    await box.put('birthday_checked_date', todayStr);

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return;
      final row = await client
          .from('users_public')
          .select('date_of_birth')
          .eq('id', userId)
          .maybeSingle();
      final dob = row?['date_of_birth'] as String?;
      if (!mounted) return;
      maybeTriggerBirthdayEaster(context, dob);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final feed = context.read<EchoFeedService>();
      if (feed.echoes.isEmpty) feed.loadFeed();
      _maybeShowPermissionsOverlay();
      _maybeTriggerBirthdayEaster();
      _startFeedAdRoutine();
      // rating prompt after enough real use
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) RatingPrompt.maybeShow(context);
      });
    });
  }

  Future<void> _maybeShowPermissionsOverlay() async {
    if (!Hive.isBoxOpen('app_settings')) {
      await Hive.openBox('app_settings');
    }
    final box = Hive.box('app_settings');
    final shown = box.get(StorageKeys.permissionsPromptShown,
        defaultValue: false) as bool;
    if (shown) return;

    if (await PermissionsSheet.corePermissionsGranted()) {
      await PermissionsSheet.markPromptSeen();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const PermissionsSheet(),
    );

    await PermissionsSheet.markPromptSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedAdTimer?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _lastActiveAt = DateTime.now();
      _feedAdTimer?.cancel();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      final staleFor = DateTime.now().difference(_lastActiveAt);
      _startFeedAdRoutine();
      if (staleFor >= const Duration(minutes: 15)) {
        context.read<EchoFeedService>().refresh();
      }
    }
  }

  void _startFeedAdRoutine() {
    final adService = context.read<AdService>();
    adService.prepareFeedRoutine();
    final cooldown = adService.feedRoutineCooldownRemaining;
    _scheduleFeedAdCheck(
      cooldown > Duration.zero ? cooldown : const Duration(minutes: 30),
    );
  }

  void _scheduleFeedAdCheck(Duration delay) {
    _feedAdTimer?.cancel();
    _feedAdTimer = Timer(delay, _tryShowFeedRoutineAd);
  }

  Future<void> _tryShowFeedRoutineAd() async {
    if (!mounted) return;

    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!routeIsCurrent) {
      _scheduleFeedAdCheck(const Duration(minutes: 1));
      return;
    }

    final subscription = context.read<SubscriptionService>();
    final adService = context.read<AdService>();
    adService.prepareFeedRoutine();

    if (subscription.isPro || adService.isAdFreeActive) {
      _scheduleFeedAdCheck(const Duration(minutes: 5));
      return;
    }

    if (adService.canShowFeedRoutineAd) {
      final shown = await adService.showFeedRoutineAd();
      if (!mounted) return;
      _scheduleFeedAdCheck(
        shown ? const Duration(minutes: 30) : const Duration(minutes: 1),
      );
      return;
    }

    final cooldown = adService.feedRoutineCooldownRemaining;
    _scheduleFeedAdCheck(
      cooldown > Duration.zero
          ? cooldown + const Duration(seconds: 10)
          : const Duration(minutes: 1),
    );
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

  Future<void> _refreshFeed() async {
    if (showOfflineSnackIfNeeded(context)) return;
    final notifications = context.read<NotificationService>();
    await context.read<EchoFeedService>().refresh();
    unawaited(notifications.markFollowerEchoesRead());
  }

  Future<void> _handleFeedNavTap() async {
    if (_scrollCtrl.hasClients && _scrollCtrl.offset > 8) {
      await _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    await _refreshFeed();
  }

  List<EchoEntity> _filtered(List<EchoEntity> echoes) {
    return _filter.apply(echoes);
  }

  int _itemCount(List<EchoEntity> filtered, bool hasMore) {
    return filtered.length + (hasMore ? 1 : 0);
  }

  Widget _refreshableState(Widget child) {
    final minHeight = MediaQuery.sizeOf(context).height -
        kToolbarHeight -
        MediaQuery.paddingOf(context).top -
        MediaQuery.paddingOf(context).bottom -
        96;
    return RefreshIndicator(
      color: AppColors.fernGreen,
      onRefresh: _refreshFeed,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: minHeight.clamp(360.0, double.infinity).toDouble(),
            child: child,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = context.watch<EchoFeedService>();
    final size = MediaQuery.sizeOf(context);
    final isTablet = size.width > 700;

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
            bottomNavigationBar: AppBottomNav(
              currentLocation: '/feed',
              onFeedTap: _handleFeedNavTap,
            ),
            body: _buildBody(feed, isTablet),
          ),
        ));
  }

  Widget _buildBody(EchoFeedService feed, bool isTablet) {
    if (feed.isLoading && feed.echoes.isEmpty) {
      return _refreshableState(
          EchoLogoLoader(label: context.l('Loading feed')));
    }

    if (feed.loadState == FeedLoadState.error && feed.echoes.isEmpty) {
      return _refreshableState(
        _ErrorState(
          onRetry: () => context.read<EchoFeedService>().loadFeed(),
        ),
      );
    }

    final filtered = _filtered(feed.echoes);

    if (feed.echoes.isEmpty) return _refreshableState(const _EmptyFeed());

    if (filtered.isEmpty && _filter.isActive) {
      return _refreshableState(
        _EmptyFilter(
          onClear: () => setState(() => _filter = const FeedFilter()),
        ),
      );
    }

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: _filter.isActive
              ? _ActiveFilterBar(
                  filter: _filter,
                  onClear: () => setState(() => _filter = const FeedFilter()),
                  onTap: _openFilter,
                )
              : const SizedBox.shrink(),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: filtered.isEmpty
              ? const SizedBox.shrink()
              : _FeedPulseBar(
                  key: ValueKey('${filtered.length}_${_filter.hashCode}'),
                  echoes: filtered,
                  onTap: _refreshFeed,
                ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.fernGreen,
            onRefresh: _refreshFeed,
            child: ListView.builder(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: 120),
              itemCount: _itemCount(filtered, feed.hasMore),
              itemBuilder: (ctx, index) {
                if (index >= filtered.length) {
                  if (!feed.hasMore) return const SizedBox.shrink();
                  return const Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: EchoLogoLoader(size: 46),
                  );
                }

                return _AnimatedCard(
                  key: ValueKey(filtered[index].id),
                  echoId: filtered[index].id,
                  initialEcho: filtered[index],
                  index: index,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedPulseBar extends StatelessWidget {
  const _FeedPulseBar({
    super.key,
    required this.echoes,
    required this.onTap,
  });

  final List<EchoEntity> echoes;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final supported =
        echoes.where((echo) => echo.publicVerdict == 'supported').length;
    final open = echoes.where((echo) => echo.publicVerdict == 'open').length;
    final challenged = echoes.where((echo) {
      return echo.publicVerdict == 'not_supported' ||
          echo.publicVerdict == 'contested' ||
          echo.challengeCount > echo.supportCount;
    }).length;
    final latest = echoes.isEmpty ? '' : echoes.first.timeAgo;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Material(
          color: AppColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            onTap: () {
              HapticFeedback.selectionClick();
              unawaited(onTap());
            },
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 7,
              ),
              child: Row(
                children: [
                  _PulseChip(
                    icon: Icons.bolt_rounded,
                    label: latest.isEmpty ? 'live context' : 'fresh $latest',
                    color: AppColors.charcoal,
                  ),
                  _PulseChip(
                    icon: Icons.verified_outlined,
                    label: '$supported supported',
                    color: AppColors.fernGreenDark,
                  ),
                  _PulseChip(
                    icon: Icons.groups_2_outlined,
                    label: '$open open',
                    color: AppColors.textSecondary,
                  ),
                  _PulseChip(
                    icon: Icons.report_problem_outlined,
                    label: '$challenged challenged',
                    color: AppColors.sunsetCoralDark,
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

class _PulseChip extends StatelessWidget {
  const _PulseChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(color: color.withValues(alpha: 0.11)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
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
    if (filter.statuses.isNotEmpty) {
      parts.add('${filter.statuses.length} status');
    }
    if (filter.categories.isNotEmpty) {
      parts.add('${filter.categories.length} categories');
    }
    if (filter.sortBy != FeedSortBy.trending) {
      parts.add(filter.sortBy.label);
    }

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
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close_rounded,
                  size: 16, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedCard extends StatefulWidget {
  const _AnimatedCard({
    super.key,
    required this.echoId,
    required this.initialEcho,
    required this.index,
  });

  final String echoId;
  final EchoEntity initialEcho;
  final int index;

  @override
  State<_AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<_AnimatedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _opacity;
  late final Animation<double> _y;

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
      animation: _c,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(
          offset: Offset(0, _y.value),
          child: child,
        ),
      ),
      child: Selector<EchoFeedService, EchoEntity>(
        selector: (_, feed) => feed.echoes.firstWhere(
          (e) => e.id == widget.echoId,
          orElse: () => widget.initialEcho,
        ),
        shouldRebuild: (previous, next) => previous != next,
        builder: (context, echo, _) {
          return RepaintBoundary(
            child: EchoCard(
              echo: echo,
              onTap: () => context.push('/feed/echo/${echo.id}'),
            ),
          );
        },
      ),
    );
  }
}

class _FeedAppBar extends StatefulWidget implements PreferredSizeWidget {
  const _FeedAppBar({
    required this.filterActive,
    required this.onFilterTap,
  });

  final bool filterActive;
  final VoidCallback onFilterTap;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  State<_FeedAppBar> createState() => _FeedAppBarState();
}

class _FeedAppBarState extends State<_FeedAppBar> {
  int _gameTapCount = 0;
  DateTime? _lastGameTapAt;
  Offset? _lastLogoGlobalPosition;

  void _openSignalDrift([Offset? origin]) {
    _gameTapCount = 0;
    _lastGameTapAt = null;
    HapticFeedback.selectionClick();
    context.push('/signal-drift', extra: origin ?? _lastLogoGlobalPosition);
  }

  void _handleLogoTap() {
    // ten quick taps is the fallback when long press is missed
    final now = DateTime.now();
    if (_lastGameTapAt == null ||
        now.difference(_lastGameTapAt!) > const Duration(seconds: 3)) {
      _gameTapCount = 0;
    }
    _lastGameTapAt = now;
    _gameTapCount++;

    if (_gameTapCount == 7) {
      HapticFeedback.selectionClick();
    }
    if (_gameTapCount >= 10) {
      _openSignalDrift();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: AppColors.borderSubtle,
      title: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          _lastLogoGlobalPosition = details.globalPosition;
        },
        onTap: _handleLogoTap,
        onLongPressStart: (details) {
          _openSignalDrift(details.globalPosition);
        },
        child: Padding(
          // wider hidden target keeps the easter egg reachable on dense screens
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
        ),
      ),
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.tune_rounded, size: 22),
              onPressed: widget.onFilterTap,
              color:
                  widget.filterActive ? AppColors.charcoal : AppColors.charcoal,
              tooltip: context.l('Filter'),
            ),
            if (widget.filterActive)
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
          tooltip: context.l('Search'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _CreateFab extends StatefulWidget {
  const _CreateFab();

  @override
  State<_CreateFab> createState() => _CreateFabState();
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
    final service = context.watch<CreateEchoService>();
    final hasDraft = service.title.isNotEmpty || service.content.isNotEmpty;

    return ScaleTransition(
      scale: _scale,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTapDown: (_) => _c.forward(),
            onTapUp: (_) async {
              await _c.reverse();
              if (context.mounted) context.push('/create');
            },
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
              child:
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 22),
            ),
          ),
          if (hasDraft)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.fernGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
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
            Text(context.l('Nothing yet'),
                style: AppTypography.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l('Be the first to create an echo.'),
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
            Text(context.l('No echoes match your filters'),
                style: AppTypography.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l('Try adjusting or clearing your filters.'),
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
                context.l('Clear filters'),
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
          Text(context.l('Could not load feed'),
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
            child: Text(context.l('Try again'),
                style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
