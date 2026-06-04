// echo engine calculator
// combines math engine + decision engine into a single snapshot call
// dart mirror of sql recalculate_echo_scores used for unit testing
// and client-side optimistic ui updates before the edge function responds

import 'package:echoproof/features/echo/domain/entities/echo_status.dart';
import 'echo_math_engine.dart';
import 'echo_decision_engine.dart';

/// full snapshot of an echo's computed state
/// use this for: unit tests, optimistic ui, offline scoring previews
class EchoEngineCalculator {
  /// computes all scores and status from raw interaction data
  /// returns a typed snapshot not a raw map for safety
  static EchoSnapshot calculateEchoSnapshot({
    required int supportWeight,
    required int challengeWeight,
    required int supportCount,
    required int challengeCount,
    required int reportScore,
    required int totalInteractions,
    bool? adminVerified,
  }) {
    final trustScore = EchoMathEngine.trustScore(
      supportWeight: supportWeight,
      challengeWeight: challengeWeight,
    );

    final confidence = EchoMathEngine.confidence(
      supportWeight: supportWeight,
      challengeWeight: challengeWeight,
    );

    final controversy = EchoMathEngine.controversy(
      supportCount: supportCount,
      challengeCount: challengeCount,
    );

    final status = EchoDecisionEngine.determineStatus(
      trustScore: trustScore,
      confidence: confidence,
      controversy: controversy,
      reportScore: reportScore,
      totalInteractions: totalInteractions,
      adminVerified: adminVerified,
    );

    return EchoSnapshot(
      trustScore: trustScore,
      confidence: confidence,
      controversy: controversy,
      status: status,
    );
  }
}

/// typed result from the engine no raw maps
class EchoSnapshot {
  const EchoSnapshot({
    required this.trustScore,
    required this.confidence,
    required this.controversy,
    required this.status,
  });

  final int trustScore;
  final double confidence;
  final double controversy;
  final EchoStatus status;
}
