import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app/theme/colors.dart';
import '../../core/services/ad_service.dart';
import '../../features/subscription/presentation/services/subscription_service.dart';

/// Interstitial bottom banner shown on all logged-in screens.
/// Pro users and ad-free sessions never see this.
/// Respects the 3-per-30min frequency cap from AdService.
class BottomAdBanner extends StatefulWidget {
  const BottomAdBanner({super.key});

  @override
  State<BottomAdBanner> createState() => _BottomAdBannerState();
}

class _BottomAdBannerState extends State<BottomAdBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final adService = context.watch<AdService>();
    final subService = context.watch<SubscriptionService>();

    // Never show to pro users or during ad-free window.
    if (subService.isPro || adService.isAdFreeActive) {
      return const SizedBox.shrink();
    }

    // Only show when logged in and interstitial is ready.
    if (!adService.canShowInterstitial) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fade,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          border: Border(
            top: BorderSide(
              color: AppColors.fernGreen.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.fernGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'AD',
                style: GoogleFonts.josefinSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.fernGreen,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  await adService.showRewardedInterstitial(
                    onRewarded: () {
                      adService.onInterstitialWatched();
                    },
                  );
                },
                child: Text(
                  'Support Echoproof — watch a short ad',
                  style: GoogleFonts.josefinSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            GestureDetector(
              onTap: _dismiss,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}