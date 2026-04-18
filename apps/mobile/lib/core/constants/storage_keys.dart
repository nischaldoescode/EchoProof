// hive and flutter_secure_storage key constants
// never use raw strings for storage keys anywhere else in the app

abstract final class StorageKeys {
  // hive box: app_settings
  static const String onboardingComplete = 'onboarding_complete';
  static const String echoDraft          = 'echo_draft';
  static const String selectedCategories = 'selected_categories';

  // hive box: echo_cache
  static const String feedCache          = 'feed_cache';
  static const String feedCacheTimestamp = 'feed_cache_ts';

  // flutter_secure_storage
  static const String solanaKeypair      = 'solana_wallet_private_key';
  static const String supabaseSession    = 'supabase_session';
}