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
import '../../../../shared/widgets/brand_wordmark.dart';
import '../../../../shared/widgets/top_flow_loader.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  final _scrollCtrl = ScrollController();
  FeedFilter _filter = const FeedFilter();
  _FeedLane _lane = _FeedLane.forYou;
  int _laneSwitchEpoch = 0;
  bool _hasPlayedInitialFeedStagger = false;
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
      _maybeShowLinkNotice();
      // rating prompt after enough real use
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) RatingPrompt.maybeShow(context);
      });
    });
  }

  void _maybeShowLinkNotice() {
    final notice = GoRouterState.of(context).uri.queryParameters['notice'];
    if (notice == 'unsupported-link') {
      showInfoSnack(context, context.l('That link is not supported yet.'));
    }
  }

  Future<void> _maybeShowPermissionsOverlay() async {
    if (!Hive.isBoxOpen('app_settings')) {
      await Hive.openBox('app_settings');
    }
    final box = Hive.box('app_settings');
    final shown =
        box.get(StorageKeys.permissionsPromptShown, defaultValue: false)
            as bool;
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

  List<EchoEntity> _filtered(EchoFeedService feed) {
    final result = _filter.apply(feed.echoes);
    return switch (_lane) {
      _FeedLane.forYou => result,
      _FeedLane.following =>
        result.where((echo) => _isFollowingCandidate(echo, feed)).toList()
          ..sort(
            (a, b) => _followingScore(
              b,
              feed.followingIds,
            ).compareTo(_followingScore(a, feed.followingIds)),
          ),
    };
  }

  bool _isFollowingCandidate(EchoEntity echo, EchoFeedService feed) {
    return feed.followingIds.contains(echo.userId) ||
        echo.socialContext != null ||
        echo.previewReplies.any((reply) => reply.isFromFollowed);
  }

  double _followingScore(EchoEntity echo, Set<String> followingIds) {
    final authoredByFollow = followingIds.contains(echo.userId) ? 120.0 : 0.0;
    final supportedByFollow = echo.socialContext == null ? 0.0 : 60.0;
    final repliedByFollow =
        echo.previewReplies.any((reply) => reply.isFromFollowed) ? 54.0 : 0.0;
    final proofWeight = echo.proofCount * 5.0;
    final replyWeight = echo.replyCount * 2.5;
    final verdictWeight = switch (echo.publicVerdict) {
      'supported' => 24.0,
      'contested' => -18.0,
      'needs_context' => -12.0,
      'insufficient_context' => -32.0,
      'not_supported' => -100.0,
      _ => 0.0,
    };

    return authoredByFollow +
        supportedByFollow +
        repliedByFollow +
        proofWeight +
        replyWeight +
        echo.confidenceScore * 0.08 +
        echo.trustScore * 0.12 +
        verdictWeight;
  }

  int _itemCount(List<EchoEntity> filtered, bool hasMore) {
    return filtered.length + (hasMore ? 1 : 0);
  }

  void _changeLane(_FeedLane lane) {
    if (_lane == lane) return;
    HapticFeedback.selectionClick();
    setState(() {
      _lane = lane;
      _laneSwitchEpoch++;
      _hasPlayedInitialFeedStagger = true;
    });
  }

  Widget _refreshableState(Widget child) {
    final minHeight =
        MediaQuery.sizeOf(context).height -
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
          body: Stack(
            children: [
              _buildBody(feed, isTablet),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: TopFlowLoader(
                  visible:
                      feed.isLoading ||
                      feed.loadState == FeedLoadState.loadingMore,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(EchoFeedService feed, bool isTablet) {
    if (feed.isLoading && feed.echoes.isEmpty) {
      return _refreshableState(
        EchoLogoLoader(label: context.l('Loading feed')),
      );
    }

    if (feed.loadState == FeedLoadState.error && feed.echoes.isEmpty) {
      return _refreshableState(
        _ErrorState(onRetry: () => context.read<EchoFeedService>().loadFeed()),
      );
    }

    final filtered = _filtered(feed);

    if (feed.echoes.isEmpty) return _refreshableState(const _EmptyFeed());

    if (filtered.isEmpty && _lane != _FeedLane.forYou) {
      return _refreshableState(
        _EmptyLane(
          lane: _lane,
          onReset: () => setState(() => _lane = _FeedLane.forYou),
        ),
      );
    }

    if (filtered.isEmpty && _filter.isActive) {
      return _refreshableState(
        _EmptyFilter(
          onClear: () => setState(() => _filter = const FeedFilter()),
        ),
      );
    }

    return Column(
      children: [
        _FeedModeTabs(selected: _lane, onChanged: _changeLane),
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            reverseDuration: const Duration(milliseconds: 90),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0.018, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: RefreshIndicator(
              key: ValueKey('feed-lane-$_laneSwitchEpoch'),
              color: AppColors.fernGreen,
              onRefresh: _refreshFeed,
              child: ListView.builder(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 2, bottom: 92),
                itemCount: _itemCount(filtered, feed.hasMore),
                itemBuilder: (ctx, index) {
                  if (index >= filtered.length) {
                    if (!feed.hasMore) return const SizedBox.shrink();
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: EchoLogoLoader(size: 46),
                    );
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: _AnimatedCard(
                        key: ValueKey('${_lane.name}-${filtered[index].id}'),
                        echo: filtered[index],
                        index: index,
                        stagger: !_hasPlayedInitialFeedStagger,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _FeedLane { forYou, following }

class _FeedModeTabs extends StatelessWidget {
  const _FeedModeTabs({required this.selected, required this.onChanged});

  final _FeedLane selected;
  final ValueChanged<_FeedLane> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      (lane: _FeedLane.forYou, icon: Icons.eco_outlined, label: 'For you'),
      (
        lane: _FeedLane.following,
        icon: Icons.group_outlined,
        label: 'Following',
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 2, AppSpacing.lg, 0),
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: _FeedModeTab(
                  icon: item.icon,
                  label: item.label,
                  selected: selected == item.lane,
                  onTap: () => onChanged(item.lane),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedModeTab extends StatelessWidget {
  const _FeedModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected ? AppColors.fernGreen : Colors.transparent,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? AppColors.fernGreenDark
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.josefinSans(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? AppColors.fernGreenDark
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLane extends StatelessWidget {
  const _EmptyLane({required this.lane, required this.onReset});

  final _FeedLane lane;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (lane) {
      _FeedLane.following => (
        Icons.group_outlined,
        'Nothing from follows yet',
        'Follow people or wait for their echoes and replies to appear here.',
      ),
      _FeedLane.forYou => (
        Icons.eco_outlined,
        'Your feed is quiet',
        'Fresh echoes will appear here soon.',
      ),
    };

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 42, color: AppColors.fernGreen),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l(title),
            textAlign: TextAlign.center,
            style: AppTypography.textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Text(
            context.l(message),
            textAlign: TextAlign.center,
            style: AppTypography.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: onReset,
            child: Text(context.l('Back to For you')),
          ),
        ],
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
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
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
    required this.echo,
    required this.index,
    required this.stagger,
  });

  final EchoEntity echo;
  final int index;
  final bool stagger;

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
      duration: const Duration(milliseconds: 240),
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    _y = Tween<double>(
      begin: 8,
      end: 0,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

    final delay = widget.stagger && widget.index < 5
        ? Duration(milliseconds: widget.index * 22)
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
        child: Transform.translate(offset: Offset(0, _y.value), child: child),
      ),
      child: Builder(
        builder: (context) {
          final echo = widget.echo;
          final followedReply = _followedReplyFor(echo);
          final hasThread = followedReply != null;
          return RepaintBoundary(
            child: Column(
              children: [
                EchoCard(
                  echo: echo,
                  showReplyPreview: false,
                  showThreadTail: hasThread,
                  onTap: () => context.push('/feed/echo/${echo.id}'),
                ),
                if (followedReply != null)
                  EchoReplyPreviewCard(
                    detached: true,
                    reply: followedReply,
                    totalReplyCount: echo.replyCount,
                    onHashtagTap: _openHashtag,
                    onTap: () => _openReplies(echo),
                    onAuthorTap: _openReplyAuthor,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  EchoReplyPreview? _followedReplyFor(EchoEntity echo) {
    for (final reply in echo.previewReplies) {
      if (reply.isFromFollowed) return reply;
    }
    return null;
  }

  void _openReplies(EchoEntity echo) {
    context.push(
      '/echo/${echo.id}/replies'
      '?author=${Uri.encodeComponent(echo.username)}'
      '&content=${Uri.encodeComponent(echo.content)}'
      '&authorId=${Uri.encodeComponent(echo.userId)}'
      '${echo.userAvatarUrl == null ? '' : '&avatar=${Uri.encodeComponent(echo.userAvatarUrl!)}'}',
    );
  }

  void _openHashtag(String tag) {
    final normalized = tag.startsWith('#') || tag.startsWith('~')
        ? tag
        : '#$tag';
    context.push('/search?q=${Uri.encodeQueryComponent(normalized)}');
  }

  void _openReplyAuthor(String username, String? userId) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty && userId == currentUserId) {
      context.push('/profile');
      return;
    }
    context.push('/profile/${Uri.encodeComponent(username)}');
  }
}

class _FeedAppBar extends StatefulWidget implements PreferredSizeWidget {
  const _FeedAppBar({required this.filterActive, required this.onFilterTap});

  final bool filterActive;
  final VoidCallback onFilterTap;

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  State<_FeedAppBar> createState() => _FeedAppBarState();
}

class _FeedAppBarState extends State<_FeedAppBar> {
  int _gameTapCount = 0;
  DateTime? _lastGameTapAt;
  Offset? _lastLogoGlobalPosition;
  late final Future<String?> _avatarFuture;

  @override
  void initState() {
    super.initState();
    _avatarFuture = _loadAvatarUrl();
  }

  Future<String?> _loadAvatarUrl() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await client
          .from('users_public')
          .select('avatar_url')
          .eq('id', userId)
          .maybeSingle();
      return row?['avatar_url'] as String?;
    } catch (_) {
      return null;
    }
  }

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
      toolbarHeight: 58,
      titleSpacing: AppSpacing.md,
      shape: const Border(
        bottom: BorderSide(color: AppColors.borderSubtle, width: 0.5),
      ),
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
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: const EchoProofWordmark(
            fontSize: 23,
            proofColor: AppColors.fernGreenDark,
          ),
        ),
      ),
      actions: [
        _FeedHeaderIconButton(
          icon: Icons.search_rounded,
          onPressed: () => context.push('/search'),
          tooltip: context.l('Search'),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _FeedHeaderIconButton(
              icon: Icons.tune_rounded,
              onPressed: widget.onFilterTap,
              tooltip: context.l('Filter'),
              selected: widget.filterActive,
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
        FutureBuilder<String?>(
          future: _avatarFuture,
          builder: (context, snapshot) => _FeedHeaderAvatarButton(
            avatarUrl: snapshot.data,
            onPressed: () => context.push('/profile'),
            tooltip: context.l('Profile'),
          ),
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}

class _FeedHeaderAvatarButton extends StatelessWidget {
  const _FeedHeaderAvatarButton({
    required this.avatarUrl,
    required this.onPressed,
    required this.tooltip,
  });

  final String? avatarUrl;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final imageProvider = avatarImageProvider(avatarUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderSubtle),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageProvider == null
                ? const Icon(
                    Icons.person_rounded,
                    size: 19,
                    color: AppColors.textSecondary,
                  )
                : Image(
                    image: imageProvider,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.person_rounded,
                      size: 19,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _FeedHeaderIconButton extends StatelessWidget {
  const _FeedHeaderIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? AppColors.fernGreenLight
              : AppColors.surfaceSecondary,
          foregroundColor: selected
              ? AppColors.fernGreenDark
              : AppColors.charcoal,
          minimumSize: const Size(36, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 21),
      ),
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
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
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
              child: const Icon(
                Icons.edit_rounded,
                color: Colors.white,
                size: 22,
              ),
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
              child: const Icon(
                Icons.wb_sunny_outlined,
                size: 36,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              context.l('Nothing yet'),
              style: AppTypography.textTheme.headlineSmall,
            ),
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
            const Icon(
              Icons.filter_alt_off_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              context.l('No echoes match your filters'),
              style: AppTypography.textTheme.titleMedium,
            ),
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
          const Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            context.l('Could not load feed'),
            style: AppTypography.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.charcoal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              context.l('Try again'),
              style: GoogleFonts.josefinSans(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
