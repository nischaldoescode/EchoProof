// subscribe screen pro plan purchase
// shows features, pricing, native purchase flow
// google admob shown to free users only

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/snack.dart';
import '../../../../app/theme/colors.dart';
import '../../../../app/theme/spacing.dart';
import '../services/subscription_service.dart';

class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  SubscriptionService? _subscription;
  Timer? _toastTimer;
  String? _localToast;
  int _lastDiagnosticSerial = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<SubscriptionService>();
    if (_subscription == service) return;

    _subscription?.removeListener(_handleSubscriptionDiagnostics);
    _subscription = service;
    _lastDiagnosticSerial = service.checkoutDiagnosticSerial;
    service.addListener(_handleSubscriptionDiagnostics);
  }

  @override
  void dispose() {
    AppLogger.info('subscription ui: subscribe screen disposed');
    _toastTimer?.cancel();
    _subscription?.removeListener(_handleSubscriptionDiagnostics);
    _subscription?.releaseCheckoutUi(reason: 'subscribe screen disposed');
    super.dispose();
  }

  void _handleSubscriptionDiagnostics() {
    final service = _subscription;
    if (!mounted || service == null) return;
    if (service.checkoutDiagnosticSerial == _lastDiagnosticSerial) return;

    _lastDiagnosticSerial = service.checkoutDiagnosticSerial;
    final message = service.checkoutDiagnostic;
    if (message == null || message.trim().isEmpty) {
      _toastTimer?.cancel();
      setState(() => _localToast = null);
      return;
    }

    AppLogger.info('subscription ui: local toast "$message"');
    setState(() => _localToast = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _localToast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionService>();

    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAF7),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 210,
                pinned: true,
                elevation: 0,
                scrolledUnderElevation: 6,
                shadowColor: Colors.black.withValues(alpha: 0.18),
                surfaceTintColor: Colors.transparent,
                backgroundColor: const Color(0xFF15201A),
                foregroundColor: Colors.white,
                titleSpacing: 0,
                flexibleSpace: const _ProFlexibleSpace(),
                title: const _ProAppBarTitle(),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      _Entrance(
                        delay: const Duration(milliseconds: 80),
                        child: sub.isPro
                            ? Column(
                                children: [
                                  _ActiveSubscriptionCard(service: sub),
                                  if (sub.currentPlan == 'pro_monthly') ...[
                                    const SizedBox(height: AppSpacing.md),
                                    _PricingSection(
                                      service: sub,
                                      yearlyOnly: true,
                                    ),
                                  ],
                                ],
                              )
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
                                AppLogger.info(
                                    'subscription ui: restore tapped');
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
                          sub.isRestoring
                              ? 'Restoring...'
                              : 'Restore purchases',
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
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 16 + bottomPadding,
            child: _SubscriptionLocalToast(message: _localToast),
          ),
        ],
      ),
    );
  }
}

class _ProFlexibleSpace extends StatelessWidget {
  const _ProFlexibleSpace();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final topPadding = MediaQuery.paddingOf(context).top;
        final minHeight = kToolbarHeight + topPadding;
        final range = (210 - minHeight).clamp(1.0, 210.0);
        final expanded = ((constraints.maxHeight - minHeight) / range)
            .clamp(0.0, 1.0)
            .toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            const _ProHeader(),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: 1 - expanded,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF15201A),
                        Color(0xFF1E3329),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProAppBarTitle extends StatelessWidget {
  const _ProAppBarTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: const Icon(
            Icons.star_rounded,
            color: Color(0xFF79C894),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Echoproof Pro',
          style: GoogleFonts.josefinSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubscriptionLocalToast extends StatelessWidget {
  const _SubscriptionLocalToast({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: message == null
            ? const SizedBox.shrink(key: ValueKey('empty-subscription-toast'))
            : Container(
                key: ValueKey(message),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF17221C).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF79C894),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message!,
                        style: GoogleFonts.josefinSans(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 190;
              final topGap = compact ? 32.0 : 44.0;
              final iconSize = compact ? 50.0 : 58.0;
              final iconGlyphSize = compact ? 30.0 : 34.0;
              final titleSize = compact ? 28.0 : 32.0;
              final subtitleSize = compact ? 12.0 : 13.0;

              return Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: topGap),
                      Transform.scale(
                        scale: pulse,
                        child: Container(
                          width: iconSize,
                          height: iconSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.08),
                            border: Border.all(
                              color: const Color(0xFF4CAF6E)
                                  .withValues(alpha: 0.45),
                            ),
                          ),
                          child: Icon(
                            Icons.star_rounded,
                            color: const Color(0xFF4CAF6E),
                            size: iconGlyphSize,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      Text(
                        'Pro',
                        style: GoogleFonts.josefinSans(
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      Text(
                        'Unlock the full Echoproof experience',
                        style: GoogleFonts.josefinSans(
                          fontSize: subtitleSize,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PricingSection extends StatefulWidget {
  const _PricingSection({
    required this.service,
    this.yearlyOnly = false,
  });

  final SubscriptionService service;
  final bool yearlyOnly;

  @override
  State<_PricingSection> createState() => _PricingSectionState();
}

class _PricingSectionState extends State<_PricingSection> {
  bool _yearlySelected = false;
  String? _lastShownMessage;
  bool _wasPro = false;

  @override
  void initState() {
    super.initState();
    _yearlySelected = widget.yearlyOnly;
    _wasPro = widget.service.isPro;
    widget.service.addListener(_handleSubscriptionUpdate);
  }

  @override
  void didUpdateWidget(covariant _PricingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yearlyOnly != widget.yearlyOnly) {
      _yearlySelected = widget.yearlyOnly;
    }
    if (oldWidget.service != widget.service) {
      oldWidget.service.removeListener(_handleSubscriptionUpdate);
      _wasPro = widget.service.isPro;
      widget.service.addListener(_handleSubscriptionUpdate);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_handleSubscriptionUpdate);
    super.dispose();
  }

  void _handleSubscriptionUpdate() {
    if (!mounted) return;

    final error = widget.service.error;
    if (error != null && error != _lastShownMessage) {
      AppLogger.info('subscription ui: showing subscription message $error');
      _lastShownMessage = error;
      if (_usesLocalToastOnly(error)) return;

      if (_isInfoMessage(error)) {
        showInfoSnack(context, error);
      } else if (_isWarningMessage(error)) {
        showWarningSnack(context, error);
      } else {
        showErrorSnack(context, error);
      }
    }

    if (!_wasPro && widget.service.isPro) {
      _lastShownMessage = 'pro-active';
      AppLogger.info('subscription ui: pro activated message shown');
      showSuccessSnack(context, 'Echoproof Pro is active.');
    }
    _wasPro = widget.service.isPro;
  }

  bool _usesLocalToastOnly(String message) {
    final lower = message.toLowerCase();
    return lower.contains('google play did not send') ||
        lower.contains('pro will activate automatically');
  }

  bool _isInfoMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('cancelled') ||
        lower.contains('already own') ||
        lower.contains('no previous') ||
        lower.contains('not charged');
  }

  bool _isWarningMessage(String message) {
    final lower = message.toLowerCase();
    return lower.contains('offline') ||
        lower.contains('unavailable') ||
        lower.contains('network') ||
        lower.contains('checkout did not finish') ||
        lower.contains('google play');
  }

  @override
  Widget build(BuildContext context) {
    final monthly = widget.service.monthlyProduct;
    final yearly = widget.service.yearlyProduct;
    final selectedProduct = _yearlySelected
        ? widget.service.yearlyProduct
        : widget.service.monthlyProduct;
    final selectedPrice = _yearlySelected
        ? yearly?.price ?? '\$39.99'
        : monthly?.price ?? '\$4.99';
    final checkoutMessage =
        widget.service.checkoutDiagnostic?.toLowerCase() ?? '';
    final checkoutLabel = checkoutMessage.contains('waiting')
        ? 'Waiting for Google Play...'
        : checkoutMessage.contains('still opening')
            ? 'Opening Google Play...'
            : 'Opening checkout...';
    final busyLabel = widget.service.isRestoring
        ? 'Restoring purchases...'
        : widget.service.isCheckoutInProgress
            ? checkoutLabel
            : 'Loading plans...';
    final statusText = widget.service.isLoading
        ? widget.service.checkoutDiagnostic ??
            (widget.service.isCheckoutInProgress
                ? 'Google Play checkout opens in a secure window.'
                : 'Loading Google Play plans for this device.')
        : widget.service.error;
    final tabsEnabled = !widget.service.isLoading;

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
              if (widget.yearlyOnly)
                _UpgradeHeader(price: yearly?.price ?? '\$39.99')
              else
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
                        enabled: tabsEnabled,
                        onTap: () => setState(() => _yearlySelected = false),
                      ),
                      const SizedBox(width: 4),
                      _PlanTab(
                        label: 'Yearly',
                        price: yearly?.price ?? '\$39.99',
                        badge: 'Save 33%',
                        selected: _yearlySelected,
                        enabled: tabsEnabled,
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
                      : () async {
                          final product = selectedProduct;
                          AppLogger.info(
                            'subscription ui: checkout tapped plan=${_yearlySelected ? 'yearly' : 'monthly'} product=${product?.id ?? 'missing'}',
                          );
                          if (product != null) {
                            widget.service.purchase(product);
                            return;
                          }

                          AppLogger.warn(
                            'subscription ui: selected product missing, reloading products',
                          );
                          await widget.service.reloadProducts();
                          if (!context.mounted) return;
                          showWarningSnack(
                            context,
                            _yearlySelected
                                ? 'Yearly Pro is not available from Google Play yet. Check the product id and active base plan.'
                                : 'Monthly Pro is not available from Google Play yet. Check the product id and active base plan.',
                          );
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
                          : widget.yearlyOnly
                              ? 'Upgrade to yearly — $selectedPrice'
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
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: statusText == null
                    ? const SizedBox.shrink(key: ValueKey('no-status'))
                    : _CheckoutStatusBanner(
                        key: ValueKey(statusText),
                        message: statusText,
                        loading: widget.service.isLoading,
                      ),
              ),
              if (statusText != null) const SizedBox(height: AppSpacing.md),
              if (widget.service.showBillingDiagnostics &&
                  widget.service.billingDebugLog.isNotEmpty) ...[
                _BillingDiagnosticsPanel(lines: widget.service.billingDebugLog),
                const SizedBox(height: AppSpacing.md),
              ],
              const _PriorityNote(),
            ],
          ),
        ),
      ],
    );
  }
}

class _BillingDiagnosticsPanel extends StatelessWidget {
  const _BillingDiagnosticsPanel({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    // newest events appear first so testers can screenshot the current state
    final visibleLines = lines.reversed.take(28).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF101812),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                size: 15,
                color: Color(0xFF79C894),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Billing diagnostics',
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                'internal',
                style: GoogleFonts.josefinSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF79C894),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: SelectableText(
                visibleLines.join('\n'),
                style: GoogleFonts.robotoMono(
                  fontSize: 10,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutStatusBanner extends StatelessWidget {
  const _CheckoutStatusBanner({
    super.key,
    required this.message,
    required this.loading,
  });

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.98, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: loading
              ? AppColors.fernGreenLight
              : AppColors.surfaceSecondary.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: loading
                ? AppColors.fernGreen.withValues(alpha: 0.18)
                : AppColors.borderSubtle,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.fernGreen.withValues(alpha: 0.9),
                    ),
                  )
                : const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.josefinSans(
                  fontSize: 11,
                  color: loading
                      ? AppColors.fernGreenDark
                      : AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeHeader extends StatelessWidget {
  const _UpgradeHeader({required this.price});

  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.fernGreenLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.fernGreen.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.upgrade_rounded, color: AppColors.fernGreen),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade to yearly',
                  style: GoogleFonts.josefinSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
                Text(
                  '$price · Google Play applies the plan change',
                  style: GoogleFonts.josefinSans(
                    fontSize: 11,
                    color: AppColors.fernGreenDark,
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
    this.enabled = true,
    this.badge,
  });
  final String label;
  final String price;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
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
                      color: !enabled
                          ? AppColors.textTertiary.withValues(alpha: 0.55)
                          : selected
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
                      color: !enabled
                          ? AppColors.textTertiary.withValues(alpha: 0.55)
                          : selected
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
                                  color: enabled
                                      ? AppColors.fernGreenLight
                                      : AppColors.surfaceSecondary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  badge!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.josefinSans(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: enabled
                                        ? AppColors.fernGreenDark
                                        : AppColors.textTertiary
                                            .withValues(alpha: 0.6),
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
  const _ActiveSubscriptionCard({required this.service});

  final SubscriptionService service;

  @override
  Widget build(BuildContext context) {
    final isYearly = service.currentPlan == 'pro_yearly';
    final plan = isYearly ? 'Yearly Pro' : 'Monthly Pro';
    final expires = service.expiresAt;
    final status = _statusLabel(service.subscriptionStatus);

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
                      expires == null
                          ? '$plan · $status'
                          : '$plan · $status · expires ${_formatDate(expires)}',
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

String _statusLabel(String? status) {
  return switch (status) {
    'grace_period' => 'grace period',
    'on_hold' => 'on hold',
    'paused' => 'paused',
    'cancelled' || 'canceled' => 'cancelled',
    'expired' => 'expired',
    _ => 'active',
  };
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
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
