// ad service
// manages rewarded and rewarded interstitial ads
// integrates with subscription service — pro users never see ads
// rewarded ads give users 1 hour of ad-free browsing

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../constants/ad_constants.dart';
import '../utils/logger.dart';

class AdService extends ChangeNotifier {
  RewardedAd?              _rewardedAd;
  RewardedInterstitialAd?  _rewardedInterstitialAd;

  bool _rewardedReady             = false;
  bool _rewardedInterstitialReady = false;
  bool _isLoadingRewarded         = false;
  bool _isLoadingInterstitial     = false;

  // tracks when the user last earned an ad-free period
  DateTime? _adFreeUntil;

  bool get rewardedReady             => _rewardedReady;
  bool get rewardedInterstitialReady => _rewardedInterstitialReady;

  // returns true if user earned ad-free time and it has not expired
  bool get isAdFreeActive {
    if (_adFreeUntil == null) return false;
    return DateTime.now().isBefore(_adFreeUntil!);
  }

  // how many minutes of ad-free time remain
  int get adFreeMinutesRemaining {
    if (_adFreeUntil == null) return 0;
    final remaining = _adFreeUntil!.difference(DateTime.now());
    return remaining.isNegative ? 0 : remaining.inMinutes;
  }

  AdService() {
    _initialize();
  }

  Future<void> _initialize() async {
    await MobileAds.instance.initialize();
    AppLogger.info('admob: initialized');

    // load both ad types on startup
    loadRewarded();
    loadRewardedInterstitial();
  }

  // -----------------------------------------------------------------------
  // rewarded ad — user chooses to watch for a reward
  // -----------------------------------------------------------------------

  void loadRewarded() {
    if (_isLoadingRewarded || _rewardedReady) return;
    _isLoadingRewarded = true;

    RewardedAd.load(
      adUnitId: AdConstants.rewarded,
      request:  const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd        = ad;
          _rewardedReady     = true;
          _isLoadingRewarded = false;
          AppLogger.info('admob: rewarded ad loaded');
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _isLoadingRewarded = false;
          AppLogger.warn('admob: rewarded ad failed to load — ${error.message}');
          // retry after 30 seconds
          Timer(const Duration(seconds: 30), loadRewarded);
        },
      ),
    );
  }

  // shows the rewarded ad
  // onRewarded is called when the user earns the reward (watched full ad)
  // returns false if no ad is ready
  Future<bool> showRewarded({
    required void Function() onRewarded,
    void Function()? onDismissed,
  }) async {
    if (_rewardedAd == null || !_rewardedReady) {
      loadRewarded();
      return false;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd    = null;
        _rewardedReady = false;
        notifyListeners();
        onDismissed?.call();
        // preload next ad
        loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedAd    = null;
        _rewardedReady = false;
        notifyListeners();
        loadRewarded();
        AppLogger.error('admob: rewarded show failed', error);
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (_, reward) {
        AppLogger.info('admob: user earned reward ${reward.type} ${reward.amount}');
        // grant 60 minutes of ad-free browsing
        _adFreeUntil = DateTime.now().add(const Duration(hours: 1));
        notifyListeners();
        onRewarded();
      },
    );

    return true;
  }

  // -----------------------------------------------------------------------
  // rewarded interstitial — plays automatically, user can skip after 5s
  // -----------------------------------------------------------------------

  void loadRewardedInterstitial() {
    if (_isLoadingInterstitial || _rewardedInterstitialReady) return;
    _isLoadingInterstitial = true;

    RewardedInterstitialAd.load(
      adUnitId: AdConstants.rewardedInterstitial,
      request:  const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitialAd    = ad;
          _rewardedInterstitialReady = true;
          _isLoadingInterstitial     = false;
          AppLogger.info('admob: rewarded interstitial loaded');
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _isLoadingInterstitial = false;
          AppLogger.warn('admob: interstitial failed — ${error.message}');
          Timer(const Duration(seconds: 60), loadRewardedInterstitial);
        },
      ),
    );
  }

  // shows rewarded interstitial
  // typically shown after user creates 3 echoes or opens app 5 times
  Future<bool> showRewardedInterstitial({
    required void Function() onRewarded,
    void Function()? onDismissed,
  }) async {
    if (_rewardedInterstitialAd == null || !_rewardedInterstitialReady) {
      loadRewardedInterstitial();
      return false;
    }

    _rewardedInterstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedInterstitialAd    = null;
        _rewardedInterstitialReady = false;
        notifyListeners();
        onDismissed?.call();
        loadRewardedInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _rewardedInterstitialAd    = null;
        _rewardedInterstitialReady = false;
        notifyListeners();
        loadRewardedInterstitial();
      },
    );

    await _rewardedInterstitialAd!.show(
      onUserEarnedReward: (_, reward) {
        _adFreeUntil = DateTime.now().add(const Duration(hours: 1));
        notifyListeners();
        onRewarded();
      },
    );

    return true;
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedInterstitialAd?.dispose();
    super.dispose();
  }
}