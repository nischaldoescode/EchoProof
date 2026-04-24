// admob ad unit ids
// app id: ca-app-pub-8724974575673217~1448463596
// never use test ids in production builds

abstract final class AdConstants {
  // -----------------------------------------------------------------------
  // production ids — your real admob units
  // -----------------------------------------------------------------------
  static const _rewardedProd             = 'ca-app-pub-8724974575673217/8341175005';
  static const _rewardedInterstitialProd = 'ca-app-pub-8724974575673217/9069074954';

  // -----------------------------------------------------------------------
  // test ids — always use these while developing
  // google provides these officially — they never charge or count impressions
  // -----------------------------------------------------------------------
  static const _rewardedTest             = 'ca-app-pub-3940256099942544/5224354917';
  static const _rewardedInterstitialTest = 'ca-app-pub-3940256099942544/5354046379';

  // -----------------------------------------------------------------------
  // public getters — switch automatically based on build mode
  // -----------------------------------------------------------------------
  static String get rewarded =>
      const bool.fromEnvironment('dart.vm.product')
          ? _rewardedProd
          : _rewardedTest;

  static String get rewardedInterstitial =>
      const bool.fromEnvironment('dart.vm.product')
          ? _rewardedInterstitialProd
          : _rewardedInterstitialTest;
}