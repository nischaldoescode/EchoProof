// app-wide constants
// single source of truth for limits, keys, and ecosystem terminology

abstract final class AppConstants {
  // signal (hashtag equivalent) prefix character
  // signals use ~ instead of # to match the echo wave brand
  static const String signalPrefix = '~';

  // content limits
  static const int echoTitleMaxLength = 120;
  static const int echoContentMaxLength = 308;
  static const int signalMaxLength = 32;
  static const int maxSignalsPerEcho = 5;
  static const int proofMaxSizeBytes = 1024 * 1024; // 1 mb

  // rate limits (client-side soft enforcement)
  // server enforces the real limits in edge functions
  static const int maxEchoesPerHour = 5;
  static const int maxInteractionsPerHour = 50;

  // trust engine thresholds must match 003_trust_engine.sql exactly
  static const int verifiedTrustThreshold = 50;
  static const double verifiedConfidenceThreshold = 70.0;
  static const double controversyThreshold = 0.6;
  static const int controversyMinInteractions = 10;
  static const int underReviewReportScore = 20;
  static const int hiddenReportScore = 70;

  // proof stake in lamports (1 sol = 1,000,000,000 lamports)
  static const int proofStakeLamports = 1000000; // 0.001 sol

  // solana
  static const String solanaExplorerBase = 'https://explorer.solana.com/tx';
  static const String solanaMemoProgram =
      'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
}
