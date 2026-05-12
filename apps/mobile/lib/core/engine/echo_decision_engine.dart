// echo decision engine
// maps computed scores to a canonical echo status
// imports EchoStatus from domain layer — never redefines it

import 'package:echoproof/features/echo/domain/entities/echo_status.dart';

/// pure stateless engine — no db, no flutter dependencies.
/// mirrors the sql function recalculate_echo_scores case logic exactly.
/// if you change thresholds here, update 003_trust_engine.sql to match.
class EchoDecisionEngine {
  /// determines the correct EchoStatus from computed score inputs.
  ///
  /// [trustScore]        net weighted support minus challenge
  /// [confidence]        percentage of weighted interactions that are supportive (0-100)
  /// [controversy]       balance ratio 0.0 (one-sided) to 1.0 (perfectly split)
  /// [reportScore]       sum of reporter trust weights
  /// [totalInteractions] raw count of all support + challenge interactions
  /// [adminVerified]     null = no override, true = force verified, false = force rejected
  static EchoStatus determineStatus({
    required int trustScore,
    required double confidence,
    required double controversy,
    required int reportScore,
    required int totalInteractions,
    bool? adminVerified,
  }) {
    // admin override always wins — matches sql coalesce logic
    if (adminVerified != null) {
      return adminVerified ? EchoStatus.verified : EchoStatus.rejected;
    }

    // order matters — same as sql case statement
    if (reportScore >= 70)                               return EchoStatus.hidden;
    if (reportScore >= 20 && trustScore < 10)            return EchoStatus.underReview;
    if (trustScore >= 50 && confidence >= 70)            return EchoStatus.verified;
    if (controversy >= 0.6 && totalInteractions >= 10)   return EchoStatus.controversial;
    if (trustScore < 0)                                  return EchoStatus.disputed;
    if (trustScore >= 10)                                return EchoStatus.active;

    return EchoStatus.pendingVerification;
  }
}