// api endpoint constants
// all edge function paths and third-party urls in one place

abstract final class ApiConstants {
  // supabase edge functions appended to supabase_url/functions/v1
  static const String fnOnInteraction = 'on-interaction';
  static const String fnOnReport = 'on-report';
  static const String fnOnEchoCreated = 'on-echo-created';
  static const String fnOnEchoVerified = 'on-echo-verified';
  static const String fnTrustEngine = 'trust-engine';

  // dicebear avatar api
  static const String dicebearBase = 'https://api.dicebear.com/9.x/shapes/png';
  static const int avatarSize = 128;

  // solana rpc override with solana_rpc_url env var
  static const String solanaDevnet = 'https://api.devnet.solana.com';
  static const String solanaMainnet = 'https://api.mainnet-beta.solana.com';
}
