// app_banner_ad.dart
// Adaptive banner ad shown below the bottom navigation bar.
// Pro users and ad-free sessions never see this.
// Loads automatically and animates in when ready.

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../app/theme/colors.dart';
import '../../core/services/ad_service.dart';
import '../../core/constants/ad_constants.dart';
import '../../features/subscription/presentation/services/subscription_service.dart';

class AppBannerAd extends StatefulWidget {
  const AppBannerAd({super.key});

  @override
  State<AppBannerAd> createState() => _AppBannerAdState();
}

class _AppBannerAdState extends State<AppBannerAd>
    with SingleTickerProviderStateMixin {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadBanner();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      adUnitId: AdConstants.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() => _isLoaded = true);
            _fadeCtrl.forward();
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    );
    _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    final adService = context.watch<AdService>();
    final subService = context.watch<SubscriptionService>();

    // Never show to pro users or during ad-free window
    if (subService.isPro || adService.isAdFreeActive) {
      return const SizedBox.shrink();
    }

    if (!_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          color: Colors.white,
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}
