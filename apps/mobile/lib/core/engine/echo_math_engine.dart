class EchoMathEngine {
  static int trustScore({
    required int supportWeight,
    required int challengeWeight,
  }) {
    return supportWeight - challengeWeight;
  }

  static double confidence({
    required int supportWeight,
    required int challengeWeight,
  }) {
    final total = supportWeight + challengeWeight;
    if (total == 0) return 0.0;
    return (supportWeight / total) * 100;
  }

  static double controversy({
    required int supportCount,
    required int challengeCount,
  }) {
    final maxVal = supportCount > challengeCount ? supportCount : challengeCount;
    if (maxVal == 0) return 0.0;

    final minVal = supportCount < challengeCount ? supportCount : challengeCount;
    return minVal / maxVal;
  }
}