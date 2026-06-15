// discover screen
// @params none shows trending signals by ip country or globally

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ip_hunter/ip_hunter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/localization/app_copy.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../app/app.dart';
import '../../../../shared/widgets/shimmer_loader.dart';
import '../../../../shared/widgets/brand_wordmark.dart';
import '../../../../shared/widgets/avatar_image_provider.dart';

class TrendingSignal {
  const TrendingSignal({
    required this.signal,
    required this.echoCount,
    required this.authorCount,
    required this.fairScore,
    this.countryCode,
  });
  final String signal;
  final int echoCount;
  final int authorCount;
  final double fairScore;
  final String? countryCode;
}

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  String? _selectedCountry;
  List<TrendingSignal> _signals = [];
  bool _isLoading = true;
  late final Future<String?> _avatarFuture;

  static const _countries = [
    (code: null, label: 'Global'),
    (code: 'IN', label: 'India'),
    (code: 'US', label: 'United States'),
    (code: 'GB', label: 'United Kingdom'),
    (code: 'NG', label: 'Nigeria'),
    (code: 'BR', label: 'Brazil'),
    (code: 'ID', label: 'Indonesia'),
    (code: 'PK', label: 'Pakistan'),
    (code: 'DE', label: 'Germany'),
    (code: 'JP', label: 'Japan'),
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _avatarFuture = _loadAvatarUrl();
    _detectCountryAndLoad();
    _subscribeRealtime();
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

  void _subscribeRealtime() {
    // refresh signals with light polling because signals have no direct trigger
    Future.delayed(const Duration(minutes: 2), () {
      if (mounted) {
        _loadSignals();
        _subscribeRealtime();
      }
    });
  }

  Future<void> _detectCountryAndLoad() async {
    var code = await _detectIpCountryCode();
    code ??= _supportedCountryCode(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode,
    );
    if (code != null) {
      setState(() => _selectedCountry = code);
    }

    await _loadSignals();
  }

  Future<String?> _detectIpCountryCode() async {
    try {
      final code = await IpHunter.getCountryCode().timeout(
        const Duration(seconds: 3),
      );
      final supported = _supportedCountryCode(code);
      AppLogger.info('discover: ip country ${supported ?? 'unsupported'}');
      return supported;
    } catch (e) {
      AppLogger.warn('discover: ip country lookup failed $e');
      return null;
    }
  }

  String? _supportedCountryCode(String? code) {
    if (code == null || code.isEmpty) return null;

    final normalized = code.trim().toUpperCase();
    final supported = _countries.map((c) => c.code).whereType<String>().toSet();
    return supported.contains(normalized) ? normalized : null;
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  Future<void> _loadSignals() async {
    setState(() => _isLoading = true);

    try {
      final client = Supabase.instance.client;
      List rows;

      if (_selectedCountry != null) {
        rows = await client
            .from('trending_signals_by_country')
            .select('signal, echo_count, author_count, fair_score')
            .eq('country_code', _selectedCountry!)
            .order('fair_score', ascending: false)
            .limit(20);
      } else {
        rows = await client
            .from('trending_signals_global')
            .select('signal, echo_count, author_count, fair_score')
            .order('fair_score', ascending: false)
            .limit(30);
      }

      setState(() {
        _signals = rows
            .map(
              (r) => TrendingSignal(
                signal: r['signal'] as String,
                echoCount: (r['echo_count'] as num).toInt(),
                authorCount: (r['author_count'] as num?)?.toInt() ?? 1,
                fairScore: ((r['fair_score'] as num?)?.toDouble() ?? 0)
                    .clamp(0, 999)
                    .toDouble(),
                countryCode: _selectedCountry,
              ),
            )
            .toList();
        _isLoading = false;
      });

      _entranceController.reset();
      _entranceController.forward();
    } catch (e) {
      AppLogger.error('discover: load signals failed', e);
      setState(() => _isLoading = false);
    }
  }

  void _selectCountry(String? code) {
    setState(() => _selectedCountry = code);
    _loadSignals();
  }

  @override
  Widget build(BuildContext context) {
    final matchedCountry = _countries
        .where((c) => c.code == _selectedCountry)
        .map((c) => c.label)
        .cast<String?>()
        .firstOrNull;
    final selectedCountry = _selectedCountry == null
        ? context.l('Global')
        : context.l(matchedCountry ?? _selectedCountry!);

    return SwipeNavigationWrapper(
      currentLocation: '/discover',
      child: ExitConfirmWrapper(
        child: Scaffold(
          backgroundColor: AppColors.white,
          bottomNavigationBar: const AppBottomNav(currentLocation: '/discover'),
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DiscoverTopBar(avatarFuture: _avatarFuture),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l('Discover'),
                        style: AppTypography.textTheme.headlineSmall?.copyWith(
                          color: AppColors.charcoal,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l(
                          "Find what matters. See what's gaining trust.",
                        ),
                        style: AppTypography.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                _CountryChipRail(
                  countries: _countries,
                  selectedCountry: _selectedCountry,
                  onSelect: _selectCountry,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.md,
                    AppSpacing.xl,
                    AppSpacing.sm,
                  ),
                  child: _DiscoverSectionHeader(country: selectedCountry),
                ),

                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.fernGreen,
                    onRefresh: _loadSignals,
                    child: _isLoading
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 180),
                              EchoLogoLoader(
                                label: context.l('Finding signals'),
                              ),
                            ],
                          )
                        : _signals.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 160),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.tag,
                                      size: 40,
                                      color: AppColors.textTertiary,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Text(
                                      context.l('No signals trending yet'),
                                      style: AppTypography.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: AppColors.textSecondary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final maxWidth = constraints.maxWidth >= 900
                                  ? 840.0
                                  : double.infinity;
                              return ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 96),
                                itemCount: _signals.length,
                                itemBuilder: (context, index) {
                                  final delay = index * 0.04;
                                  final end = (delay + 0.3).clamp(0.0, 1.0);
                                  final anim = Tween<double>(begin: 0, end: 1)
                                      .animate(
                                        CurvedAnimation(
                                          parent: _entranceController,
                                          curve: Interval(
                                            delay,
                                            end,
                                            curve: Curves.easeOut,
                                          ),
                                        ),
                                      );

                                  return Center(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: maxWidth,
                                      ),
                                      child: AnimatedBuilder(
                                        animation: anim,
                                        builder: (context, child) => Opacity(
                                          opacity: anim.value,
                                          child: Transform.translate(
                                            offset: Offset(
                                              0,
                                              (1 - anim.value) * 16,
                                            ),
                                            child: child,
                                          ),
                                        ),
                                        child: _SignalRow(
                                          signal: _signals[index],
                                          rank: index + 1,
                                          onTap: () => _openSignalFeed(
                                            _signals[index].signal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSignalFeed(String signal) {
    final tag = signal.startsWith('#') ? signal : '#$signal';
    context.push('/search?q=${Uri.encodeQueryComponent(tag)}');
  }
}

extension _DiscoverNullableIterable<T> on Iterable<T?> {
  T? get firstOrNull {
    for (final value in this) {
      if (value != null) return value;
    }
    return null;
  }
}

class _DiscoverTopBar extends StatelessWidget {
  const _DiscoverTopBar({required this.avatarFuture});

  final Future<String?> avatarFuture;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          const Expanded(
            child: EchoProofWordmark(
              fontSize: 24,
              proofColor: AppColors.fernGreenDark,
            ),
          ),
          IconButton(
            tooltip: context.l('Search'),
            icon: const Icon(Icons.search_rounded),
            color: AppColors.charcoal,
            onPressed: () => context.push('/search'),
          ),
          FutureBuilder<String?>(
            future: avatarFuture,
            builder: (context, snapshot) => _DiscoverAvatarButton(
              avatarUrl: snapshot.data,
              onPressed: () => context.push('/profile'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoverAvatarButton extends StatelessWidget {
  const _DiscoverAvatarButton({
    required this.avatarUrl,
    required this.onPressed,
  });

  final String? avatarUrl;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final imageProvider = avatarImageProvider(avatarUrl);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 38,
          height: 38,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceSecondary,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: imageProvider == null
              ? const Icon(
                  Icons.person_rounded,
                  color: AppColors.textSecondary,
                  size: 21,
                )
              : Image(
                  image: imageProvider,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.person_rounded,
                    color: AppColors.textSecondary,
                    size: 21,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CountryChipRail extends StatelessWidget {
  const _CountryChipRail({
    required this.countries,
    required this.selectedCountry,
    required this.onSelect,
  });

  final List<({String? code, String label})> countries;
  final String? selectedCountry;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.sm,
        ),
        itemCount: countries.length,
        itemBuilder: (context, i) {
          final c = countries[i];
          final selected = selectedCountry == c.code;

          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              onTap: () => onSelect(c.code),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.fernGreenDark
                      : AppColors.surfaceSecondary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: selected
                        ? AppColors.fernGreenDark
                        : AppColors.borderSubtle,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.code == null
                          ? Icons.public_rounded
                          : Icons.location_on_rounded,
                      size: 15,
                      color: selected ? AppColors.white : AppColors.charcoal,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      context.l(c.label),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? AppColors.white
                            : AppColors.textPrimary,
                        fontFamily: AppTypography.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiscoverSectionHeader extends StatelessWidget {
  const _DiscoverSectionHeader({required this.country});

  final String country;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.trending_up_rounded, color: AppColors.fernGreen),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l('Trending in {country}', {'country': country}),
                style: AppTypography.textTheme.titleSmall?.copyWith(
                  color: AppColors.charcoal,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                context.l('Top echoes people are talking about'),
                style: AppTypography.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({
    required this.signal,
    required this.rank,
    required this.onTap,
  });

  final TrendingSignal signal;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Material(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: AppColors.charcoal.withValues(alpha: 0.025),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? AppColors.fernGreenLight
                        : AppColors.surfaceSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: rank <= 3
                          ? AppColors.fernGreenDark
                          : AppColors.textTertiary,
                      fontFamily: AppTypography.fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              signal.signal.startsWith('#')
                                  ? signal.signal
                                  : '#${signal.signal}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                fontFamily: AppTypography.fontFamily,
                              ),
                            ),
                          ),
                          if (rank <= 3)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.fernGreenLight,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                context.l('Fair {score}', {
                                  'score': signal.fairScore.toStringAsFixed(1),
                                }),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.fernGreenDark,
                                  fontFamily: AppTypography.fontFamily,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l('{echoes} echoes · {voices} voices', {
                          'echoes': _formatCount(signal.echoCount),
                          'voices': _formatCount(signal.authorCount),
                        }),
                        style: AppTypography.textTheme.labelMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          value: (signal.fairScore / 10)
                              .clamp(0.05, 1.0)
                              .toDouble(),
                          backgroundColor: AppColors.borderSubtle,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            rank <= 3
                                ? AppColors.fernGreen
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.45,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}
