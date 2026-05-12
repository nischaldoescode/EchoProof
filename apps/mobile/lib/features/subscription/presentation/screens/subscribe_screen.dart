// subscribe screen — pro plan purchase
// shows features, pricing, native purchase flow
// google admob shown to free users only

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/snack.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../services/subscription_service.dart';

class SubscribeScreen extends StatelessWidget {
  const SubscribeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionService>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.charcoal,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: const _ProHeader(),
            ),
            title: Text(
              'Echoproof Pro',
              style: GoogleFonts.josefinSans(fontWeight: FontWeight.w700),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  _Entrance(
                    delay: const Duration(milliseconds: 80),
                    child: sub.isPro
                        ? _ActiveSubscriptionCard()
                        : _PricingSection(service: sub),
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // feature comparison
                  const _Entrance(
                    delay: Duration(milliseconds: 170),
                    child: _FeatureComparison(),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  // restore purchases
                  TextButton.icon(
                    onPressed: sub.isLoading
                        ? null
                        : () async {
                            await sub.restorePurchases();
                            if (!context.mounted) return;

                            final error = sub.error;
                            if (error != null) {
                              if (error.startsWith('No previous')) {
                                showInfoSnack(context, error);
                              } else {
                                showErrorSnack(context, error);
                              }
                              return;
                            }

                            if (sub.isPro) {
                              showSuccessSnack(
                                context,
                                'Your Pro purchase was restored.',
                              );
                            } else {
                              showInfoSnack(
                                context,
                                'Restore finished. No active Pro purchase found.',
                              );
                            }
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textTertiary,
                    ),
                    icon: sub.isRestoring
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textTertiary,
                            ),
                          )
                        : const Icon(Icons.restore_rounded, size: 16),
                    label: Text(
                      sub.isRestoring ? 'Restoring...' : 'Restore purchases',
                      style: GoogleFonts.josefinSans(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({
    required this.child,
    required this.delay,
  });

  final Widget child;
  final Duration delay;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future<void>.delayed(widget.delay, () {
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
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}

class _ProHeader extends StatefulWidget {
  const _ProHeader();

  @override
  State<_ProHeader> createState() => _ProHeaderState();
}

class _ProHeaderState extends State<_ProHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
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
      builder: (_, __) {
        final pulse = 0.98 + (_c.value * 0.04);

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  const Color(0xFF1A1A1A),
                  const Color(0xFF2D4A3E),
                  _c.value,
                )!,
                Color.lerp(
                  const Color(0xFF2D4A3E),
                  const Color(0xFF1A3A2A),
                  _c.value,
                )!,
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Transform.scale(
                  scale: pulse,
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                      border: Border.all(
                        color: const Color(0xFF4CAF6E).withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Color(0xFF4CAF6E),
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Pro',
                  style: GoogleFonts.josefinSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  'Unlock the full Echoproof experience',
                  style: GoogleFonts.josefinSans(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PricingSection extends StatefulWidget {
  const _PricingSection({required this.service});
  final SubscriptionService service;

  @override
  State<_PricingSection> createState() => _PricingSectionState();
}

class _PricingSectionState extends State<_PricingSection> {
  bool _yearlySelected = false;

  @override
  Widget build(BuildContext context) {
    final monthly = widget.service.monthlyProduct;
    final yearly = widget.service.yearlyProduct;
    final selectedPrice = _yearlySelected
        ? yearly?.price ?? '\$39.99'
        : monthly?.price ?? '\$4.99';
    final busyLabel = widget.service.isRestoring
        ? 'Restoring purchases...'
        : 'Preparing checkout...';

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              // Stable height: enough room for label, price, and the yearly badge.
              Container(
                height: 96,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _PlanTab(
                      label: 'Monthly',
                      price: monthly?.price ?? '\$4.99',
                      selected: !_yearlySelected,
                      onTap: () => setState(() => _yearlySelected = false),
                    ),
                    const SizedBox(width: 4),
                    _PlanTab(
                      label: 'Yearly',
                      price: yearly?.price ?? '\$39.99',
                      badge: 'Save 33%',
                      selected: _yearlySelected,
                      onTap: () => setState(() => _yearlySelected = true),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.service.isLoading
                      ? null
                      : () {
                          final product = _yearlySelected
                              ? widget.service.yearlyProduct
                              : widget.service.monthlyProduct;
                          if (product != null) {
                            widget.service.purchase(product);
                          }
                        },
                  icon: widget.service.isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : const Icon(Icons.star_rounded, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.charcoal,
                    disabledBackgroundColor:
                        AppColors.charcoal.withValues(alpha: 0.55),
                    foregroundColor: AppColors.white,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  label: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      widget.service.isLoading
                          ? busyLabel
                          : 'Start Pro — $selectedPrice',
                      key: ValueKey(
                        '${widget.service.isLoading}-$selectedPrice',
                      ),
                      style: GoogleFonts.josefinSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),
              const _PriorityNote(),
            ],
          ),
        ),
      ],
    );
  }
}

class _PriorityNote extends StatelessWidget {
  const _PriorityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.fernGreen.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined,
              size: 14, color: AppColors.fernGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'For maximum feed priority, verify your identity in Settings after subscribing. Verified Pro users get the highest trust weight.',
              style: GoogleFonts.josefinSans(
                fontSize: 11,
                color: AppColors.fernGreenDark,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTab extends StatelessWidget {
  const _PlanTab({
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final String label;
  final String price;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: selected ? 1 : 0.985,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? AppColors.fernGreen.withValues(alpha: 0.18)
                      : Colors.transparent,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.josefinSans(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected
                          ? AppColors.charcoal
                          : AppColors.textTertiary,
                    ),
                  ),
                  Text(
                    price,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.josefinSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? AppColors.charcoal
                          : AppColors.textTertiary,
                    ),
                  ),
                  SizedBox(
                    height: 20,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: badge == null
                          ? const SizedBox.shrink(key: ValueKey('empty-badge'))
                          : Align(
                              key: ValueKey(badge),
                              alignment: Alignment.topCenter,
                              child: Container(
                                margin: const EdgeInsets.only(top: 3),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.fernGreenLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  badge!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.fernGreenDark,
                                  ),
                                ),
                              ),
                            ),
                    ),
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

class _ActiveSubscriptionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF2D4A3E)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFF4CAF6E), size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are on Pro',
                      style: GoogleFonts.josefinSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'All features unlocked',
                      style: GoogleFonts.josefinSans(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF6E)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () => context.push('/purchase-history'),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  'View purchase history & invoices',
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    color: Colors.white54,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FeatureItem {
  final String label;
  final bool free;
  final bool pro;
  final String? freeNote;
  final String? proNote;

  const FeatureItem({
    required this.label,
    required this.free,
    required this.pro,
    this.freeNote,
    this.proNote,
  });
}

class _FeatureComparison extends StatelessWidget {
  const _FeatureComparison();

  static const List<FeatureItem> _features = [
    FeatureItem(label: 'Post echoes', free: true, pro: true),
    FeatureItem(label: 'Support & challenge echoes', free: true, pro: true),
    FeatureItem(
      label: 'Character limit',
      free: false,
      pro: true,
      freeNote: '280 chars',
      proNote: '5,000 chars',
    ),
    FeatureItem(
        label: 'Rich text (bold, italic, etc.)', free: false, pro: true),
    FeatureItem(label: 'Edit your echoes', free: false, pro: true),
    FeatureItem(label: 'Ad-free experience', free: false, pro: true),
    FeatureItem(label: 'Truth bonds', free: true, pro: true),
    FeatureItem(label: 'Priority in feed', free: false, pro: true),
    FeatureItem(label: 'Analytics on your echoes', free: false, pro: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 18, color: AppColors.fernGreen),
            const SizedBox(width: 8),
            Text(
              'What you get',
              style: GoogleFonts.josefinSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: SizedBox()),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Free',
                          style: GoogleFonts.josefinSans(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Pro',
                          style: GoogleFonts.josefinSans(
                            fontSize: 12,
                            color: AppColors.fernGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ..._features.map((f) => _FeatureRow(
                    label: f.label,
                    freeNote: f.freeNote,
                    proNote: f.proNote,
                    hasFree: f.free,
                    hasPro: f.pro,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.label,
    required this.hasFree,
    required this.hasPro,
    this.freeNote,
    this.proNote,
  });
  final String label;
  final bool hasFree;
  final bool hasPro;
  final String? freeNote;
  final String? proNote;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(vertical: 12, horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.josefinSans(
                fontSize: 13,
                color: AppColors.charcoal,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: hasFree
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        if (freeNote != null)
                          Text(
                            freeNote!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.josefinSans(
                              fontSize: 9,
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
                    )
                  : const Icon(
                      Icons.remove,
                      size: 14,
                      color: AppColors.borderMedium,
                    ),
            ),
          ),
          Expanded(
            child: Center(
              child: hasPro
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.fernGreen,
                        ),
                        if (proNote != null)
                          Text(
                            proNote!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.josefinSans(
                              fontSize: 9,
                              color: AppColors.fernGreen,
                            ),
                          ),
                      ],
                    )
                  : const Icon(
                      Icons.remove,
                      size: 14,
                      color: AppColors.borderMedium,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
