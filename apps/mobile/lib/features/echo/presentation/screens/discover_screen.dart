// discover screen
// shows trending signals (what echoproof calls hashtags — using ~ prefix)
// filters by country or global
// styled like twitter's trending page but using echoproof vocabulary

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../../../../app/theme/typography.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../core/utils/logger.dart';

class TrendingSignal {
  const TrendingSignal({
    required this.signal,
    required this.echoCount,
    this.countryCode,
  });
  final String  signal;
  final int     echoCount;
  final String? countryCode;
}

// provider: fetches trending signals from supabase
final trendingSignalsProvider = FutureProvider.family<List<TrendingSignal>, String?>(
  (ref, countryCode) async {
    final client = ref.read(supabaseProvider);

    if (countryCode != null) {
      final rows = await client
          .from('trending_signals_by_country')
          .select('signal, echo_count')
          .eq('country_code', countryCode)
          .order('echo_count', ascending: false)
          .limit(20);

      return (rows as List).map((r) => TrendingSignal(
        signal:      r['signal'] as String,
        echoCount:   (r['echo_count'] as num).toInt(),
        countryCode: countryCode,
      )).toList();
    }

    final rows = await client
        .from('trending_signals_global')
        .select('signal, echo_count')
        .order('echo_count', ascending: false)
        .limit(30);

    return (rows as List).map((r) => TrendingSignal(
      signal:    r['signal'] as String,
      echoCount: (r['echo_count'] as num).toInt(),
    )).toList();
  },
);

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen>
    with SingleTickerProviderStateMixin {

  late final AnimationController _entranceController;
  String? _selectedCountry; // null = global

  // country options — show user's country first
  // in production: detect from device locale or ip geolocation
  static const _countries = [
    (code: null,  label: 'Global'),
    (code: 'IN',  label: 'India'),
    (code: 'US',  label: 'United States'),
    (code: 'GB',  label: 'United Kingdom'),
    (code: 'NG',  label: 'Nigeria'),
    (code: 'BR',  label: 'Brazil'),
    (code: 'ID',  label: 'Indonesia'),
    (code: 'PK',  label: 'Pakistan'),
    (code: 'DE',  label: 'Germany'),
    (code: 'JP',  label: 'Japan'),
  ];

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signals = ref.watch(trendingSignalsProvider(_selectedCountry));

    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text('Discover', style: AppTypography.textTheme.titleLarge),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // country filter chips — horizontal scroll
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
                final c        = _countries[i];
                final selected = _selectedCountry == c.code;

                return GestureDetector(
                  onTap: () => setState(() => _selectedCountry = c.code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.charcoal : AppColors.softSand,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      border: Border.all(
                        color: selected ? AppColors.charcoal : AppColors.borderSubtle,
                      ),
                    ),
                    child: Text(
                      c.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? AppColors.white : AppColors.textPrimary,
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
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm,
            ),
            child: Text(
              _selectedCountry != null
                  ? 'Trending signals in ${_countries.firstWhere((c) => c.code == _selectedCountry).label}'
                  : 'Trending signals globally',
              style: AppTypography.textTheme.titleSmall,
            ),
          ),

          Expanded(
            child: signals.when(
              loading: () => const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.fernGreen,
                ),
              ),
              error: (e, _) => Center(
                child: Text('could not load signals',
                    style: AppTypography.textTheme.bodySmall),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.tag, size: 40, color: AppColors.textTertiary),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'No signals trending yet',
                          style: AppTypography.textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    // staggered entrance animation
                    final delay   = index * 0.04;
                    final end     = (delay + 0.3).clamp(0.0, 1.0);
                    final anim    = Tween<double>(begin: 0, end: 1).animate(
                      CurvedAnimation(
                        parent: _entranceController,
                        curve: Interval(delay, end, curve: Curves.easeOut),
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
                        signal:    list[index],
                        rank:      index + 1,
                        onTap:     () => _openSignalFeed(list[index].signal),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openSignalFeed(String signal) {
    AppLogger.debug('discover: opening feed for signal $signal');
    // navigate to a filtered feed showing echoes with this signal
    // for now: show a snackbar — wire to filtered feed screen later
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Showing echoes for $signal'),
        backgroundColor: AppColors.charcoal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
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
  final int            rank;
  final VoidCallback   onTap;

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
            // rank number
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: rank <= 3
                      ? AppColors.fernGreen
                      : AppColors.textTertiary,
                  fontFamily: AppTypography.fontFamily,
                ),
              ),
            ),

            const SizedBox(width: AppSpacing.sm),

            // signal name + echo count
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
                    '${_formatCount(signal.echoCount)} echoes',
                    style: AppTypography.textTheme.labelMedium,
                  ),
                ],
              ),
            ),

            // trending indicator for top 3
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
                  'Trending',
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