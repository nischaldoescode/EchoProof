// app banner ad
// shows the production admob banner below the bottom navigation
// waits for mobile ads initialization before the first request
// hides itself for pro users and temporary ad-free sessions

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
import '../../core/services/ad_service.dart';
import '../../core/constants/ad_constants.dart';
import '../../core/utils/logger.dart';
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
  bool _isLoading = false;
  bool _loadQueued = false;
  bool _blockedByConfig = false;
  Timer? _retryTimer;
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
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // queues a post-frame load so build stays pure while providers settle
  void _queueBannerLoad(AdService adService) {
    if (_isLoaded ||
        _isLoading ||
        _loadQueued ||
        _blockedByConfig ||
        _bannerAd != null) {
      return;
    }
    if (!adService.mobileAdsReady || adService.mobileAdsFailed) return;

    _loadQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadQueued = false;
      if (!mounted) return;
      _loadBanner();
    });
  }

  void _loadBanner() {
    if (_isLoading || _isLoaded || _blockedByConfig) return;
    if (!AdService.canRequestProductionUnit('banner', AdConstants.banner)) {
      setState(() => _blockedByConfig = true);
      return;
    }

    _retryTimer?.cancel();
    _isLoading = true;
    AppLogger.audit(
      'admob: banner request unit=${AdConstants.banner} size=${AdSize.banner.width}x${AdSize.banner.height}',
    );
    _bannerAd = BannerAd(
      adUnitId: AdConstants.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          final responseInfo = ad.responseInfo;
          final loadedAdapter = responseInfo?.loadedAdapterResponseInfo;
          AppLogger.audit(
            'admob: banner loaded unit=${ad.adUnitId} response_id=${responseInfo?.responseId} mediation=${responseInfo?.mediationAdapterClassName} source=${loadedAdapter?.adSourceName} adapter=${loadedAdapter?.adapterClassName} extras=${responseInfo?.responseExtras}',
          );
          if (mounted) {
            setState(() {
              _isLoaded = true;
              _isLoading = false;
            });
            _fadeCtrl.forward();
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
          _isLoaded = false;
          _isLoading = false;
          final responseInfo = error.responseInfo;
          final loadedAdapter = responseInfo?.loadedAdapterResponseInfo;
          AppLogger.audit(
            'admob: banner failed unit=${AdConstants.banner} code=${error.code} domain=${error.domain} message=${error.message} response_id=${responseInfo?.responseId} source=${loadedAdapter?.adSourceName} extras=${responseInfo?.responseExtras}',
          );
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 60), () {
            if (mounted) _loadBanner();
          });
        },
      ),
    );
    _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    final adService = context.watch<AdService>();
    final subService = context.watch<SubscriptionService>();

    // never show to pro users or during an earned ad-free window
    if (subService.isPro || adService.isAdFreeActive) {
      return const SizedBox.shrink();
    }

    _queueBannerLoad(adService);

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
        child: Align(
          alignment: Alignment.center,
          child: Container(
            margin: EdgeInsets.zero,
            color: Colors.white,
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ),
      ),
    );
  }
}
