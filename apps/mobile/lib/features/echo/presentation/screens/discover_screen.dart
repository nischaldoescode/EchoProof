// discover screen
// shows trending signals by country or globally
// uses plain StatefulWidget with supabase queries — no riverpod

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../../core/utils/logger.dart';
import '../../../../shared/widgets/app_bottom_nav.dart';
import '../../../../app/app.dart';
import '../../../../shared/widgets/shimmer_loader.dart';

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
    _detectCountryAndLoad();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    // Refresh signals every 2 minutes via realtime-like polling.
    // (echo_signals table doesn't have a natural realtime trigger, so we poll.)
    Future.delayed(const Duration(minutes: 2), () {
      if (mounted) {
        _loadSignals();
        _subscribeRealtime();
      }
    });
  }

  Future<void> _detectCountryAndLoad() async {
    final code = _supportedCountryCode(
      WidgetsBinding.instance.platformDispatcher.locale.countryCode,
    );
    if (code != null) {
      setState(() => _selectedCountry = code);
    }

    await _loadSignals();
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
            .map((r) => TrendingSignal(
                  signal: r['signal'] as String,
                  echoCount: (r['echo_count'] as num).toInt(),
                  authorCount: (r['author_count'] as num?)?.toInt() ?? 1,
                  fairScore: ((r['fair_score'] as num?)?.toDouble() ?? 0)
                      .clamp(0, 999)
                      .toDouble(),
                  countryCode: _selectedCountry,
                ))
            .toList();
        _isLoading = false;
      });

      _entranceController.reset();
      _entranceController.forward();
      // Realtime-like: also subscribe to postgres changes on echo_signals.
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
    return SwipeNavigationWrapper(
        currentLocation: '/discover',
        child: ExitConfirmWrapper(
            child: Scaffold(
          backgroundColor: AppColors.white,
          appBar: AppBar(
            title: Text('Discover', style: AppTypography.textTheme.titleLarge),
          ),
          bottomNavigationBar: const AppBottomNav(currentLocation: '/discover'),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // country filter chips
              SizedBox(
                height: 48,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  itemCount: _countries.length,
                  itemBuilder: (context, i) {
                    final c = _countries[i];
                    final selected = _selectedCountry == c.code;

                    return GestureDetector(
                      onTap: () => _selectCountry(c.code),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.charcoal
                              : AppColors.softSand,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                          border: Border.all(
                            color: selected
                                ? AppColors.charcoal
                                : AppColors.borderSubtle,
                          ),
                        ),
                        child: Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? AppColors.white
                                : AppColors.textPrimary,
                            fontFamily: AppTypography.fontFamily,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
                child: Text(
                  _selectedCountry != null
                      ? 'Trending signals in ${_countries.firstWhere((c) => c.code == _selectedCountry).label}'
                      : 'Trending signals globally',
                  style: AppTypography.textTheme.titleSmall,
                ),
              ),

              Expanded(
                child: RefreshIndicator(
                  color: AppColors.fernGreen,
                  onRefresh: _loadSignals,
                  child: _isLoading
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 180),
                            EchoLogoLoader(label: 'Finding signals'),
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
                                        'No signals trending yet',
                                        style: AppTypography
                                            .textTheme.bodyMedium
                                            ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: _signals.length,
                              itemBuilder: (context, index) {
                                final delay = index * 0.04;
                                final end = (delay + 0.3).clamp(0.0, 1.0);
                                final anim =
                                    Tween<double>(begin: 0, end: 1).animate(
                                  CurvedAnimation(
                                    parent: _entranceController,
                                    curve: Interval(delay, end,
                                        curve: Curves.easeOut),
                                  ),
                                );

                                return AnimatedBuilder(
                                  animation: anim,
                                  builder: (context, child) => Opacity(
                                    opacity: anim.value,
                                    child: Transform.translate(
                                      offset: Offset(0, (1 - anim.value) * 16),
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
                                );
                              },
                            ),
                ),
              ),
            ],
          ),
        )));
  }

  void _openSignalFeed(String signal) {
    context.push('/search?q=${Uri.encodeQueryComponent(signal)}');
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      rank <= 3 ? AppColors.fernGreen : AppColors.textTertiary,
                  fontFamily: AppTypography.fontFamily,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signal.signal,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontFamily: AppTypography.fontFamily,
                    ),
                  ),
                  Text(
                    '${_formatCount(signal.echoCount)} echoes - ${_formatCount(signal.authorCount)} voices',
                    style: AppTypography.textTheme.labelMedium,
                  ),
                ],
              ),
            ),
            if (rank <= 3)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.fernGreenLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Fair ${signal.fairScore.toStringAsFixed(1)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.fernGreenDark,
                    fontFamily: AppTypography.fontFamily,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }
}
