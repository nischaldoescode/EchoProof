// subscribe screen — pro plan purchase
// shows features, pricing, native purchase flow
// google admob shown to free users only

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
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
              background: _ProHeader(),
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
                  if (sub.isPro)
                    _ActiveSubscriptionCard()
                  else
                    _PricingSection(service: sub),

                  const SizedBox(height: AppSpacing.xl),

                  // feature comparison
                  _FeatureComparison(),

                  const SizedBox(height: AppSpacing.xxl),

                  // restore purchases
                  TextButton(
                    onPressed: () => sub.restorePurchases(),
                    child: Text(
                      'Restore purchases',
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

class _ProHeader extends StatefulWidget {
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
                const Icon(
                  Icons.star_rounded,
                  color: Color(0xFF4CAF6E),
                  size: 48,
                ),
                const SizedBox(height: 12),
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

    return Column(
      children: [
        // plan toggle
        Container(
          height: 82, // Fixed height prevents layout jitter during animation
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4F2),
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              _PlanTab(
                label: 'Monthly',
                price: monthly?.price ?? '\$4.99',
                selected: !_yearlySelected,
                onTap: () => setState(() => _yearlySelected = false),
              ),
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

        const SizedBox(height: AppSpacing.lg),

        // purchase button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.charcoal,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              widget.service.isLoading
                  ? 'Loading...'
                  : 'Start Pro — ${_yearlySelected ? yearly?.price ?? '\$39.99' : monthly?.price ?? '\$4.99'}',
              style: GoogleFonts.josefinSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.fernGreenLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 13, color: AppColors.fernGreen),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'For maximum feed priority, verify your identity in Settings after subscribing. Verified Pro users get the highest trust weight.',
                  style: GoogleFonts.josefinSans(
                    fontSize: 11,
                    color: AppColors.fernGreenDark,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Column(
            children: [
              Text(
                label,
                style: GoogleFonts.josefinSans(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.charcoal : AppColors.textTertiary,
                ),
              ),
              Text(
                price,
                style: GoogleFonts.josefinSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppColors.charcoal : AppColors.textTertiary,
                ),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.fernGreenLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.josefinSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.fernGreenDark,
                    ),
                  ),
                ),
            ],
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
        Text(
          'What you get',
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.charcoal,
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // header
        Row(
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

        const SizedBox(height: AppSpacing.sm),

        ..._features.map((f) => _FeatureRow(
              label: f.label,
              freeNote: f.freeNote,
              proNote: f.proNote,
              hasFree: f.free,
              hasPro: f.pro,
            )),
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
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        if (freeNote != null)
                          Text(
                            freeNote!,
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
                      children: [
                        const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.fernGreen,
                        ),
                        if (proNote != null)
                          Text(
                            proNote!,
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
