// unit tests for trust score calculation
// tests the sql-equivalent dart math in EchoMathEngine and EchoDecisionEngine

import 'package:flutter_test/flutter_test.dart';
import 'package:echoproof/core/engine/echo_math_engine.dart';
import 'package:echoproof/core/engine/echo_decision_engine.dart';
import 'package:echoproof/features/echo/domain/entities/echo_status.dart';

void main() {
  group('trust score math', () {
    test('positive support gives positive score', () {
      final score = EchoMathEngine.trustScore(
        supportWeight: 20,
        challengeWeight: 5,
      );
      expect(score, 15);
    });

    test('zero interactions gives zero score', () {
      final score = EchoMathEngine.trustScore(
        supportWeight: 0,
        challengeWeight: 0,
      );
      expect(score, 0);
    });

    test('more challenges than support gives negative score', () {
      final score = EchoMathEngine.trustScore(
        supportWeight: 2,
        challengeWeight: 30,
      );
      expect(score, -28);
    });
  });

  group('confidence score math', () {
    test('all support is 100 percent', () {
      final conf = EchoMathEngine.confidence(
        supportWeight: 50,
        challengeWeight: 0,
      );
      expect(conf, 100.0);
    });

    test('no interactions is zero percent', () {
      final conf = EchoMathEngine.confidence(
        supportWeight: 0,
        challengeWeight: 0,
      );
      expect(conf, 0.0);
    });

    test('even split is 50 percent', () {
      final conf = EchoMathEngine.confidence(
        supportWeight: 10,
        challengeWeight: 10,
      );
      expect(conf, 50.0);
    });
  });

  group('controversy score math', () {
    test('perfectly balanced is 1.0', () {
      final c = EchoMathEngine.controversy(
        supportCount: 10,
        challengeCount: 10,
      );
      expect(c, 1.0);
    });

    test('completely one-sided is 0.0', () {
      final c = EchoMathEngine.controversy(
        supportCount: 100,
        challengeCount: 0,
      );
      expect(c, 0.0);
    });
  });

  group('status decision logic', () {
    test('report score 70+ forces hidden', () {
      final s = EchoDecisionEngine.determineStatus(
        trustScore: 999,
        confidence: 100,
        controversy: 0,
        reportScore: 70,
        totalInteractions: 50,
      );
      expect(s, EchoStatus.hidden);
    });

    test('high trust and confidence gives verified', () {
      final s = EchoDecisionEngine.determineStatus(
        trustScore: 55,
        confidence: 75,
        controversy: 0.1,
        reportScore: 0,
        totalInteractions: 60,
      );
      expect(s, EchoStatus.verified);
    });

    test('balanced split with 10+ interactions is controversial', () {
      final s = EchoDecisionEngine.determineStatus(
        trustScore: 1,
        confidence: 51,
        controversy: 0.9,
        reportScore: 3,
        totalInteractions: 20,
      );
      expect(s, EchoStatus.controversial);
    });

    test('negative trust score is disputed', () {
      final s = EchoDecisionEngine.determineStatus(
        trustScore: -10,
        confidence: 25,
        controversy: 0.2,
        reportScore: 5,
        totalInteractions: 15,
      );
      expect(s, EchoStatus.disputed);
    });

    test('no interactions is pending verification', () {
      final s = EchoDecisionEngine.determineStatus(
        trustScore: 0,
        confidence: 0,
        controversy: 0,
        reportScore: 0,
        totalInteractions: 0,
      );
      expect(s, EchoStatus.pendingVerification);
    });

    test('admin override true forces verified regardless of scores', () {
      final s = EchoDecisionEngine.determineStatus(
        trustScore: -999,
        confidence: 1,
        controversy: 0.99,
        reportScore: 0,
        totalInteractions: 100,
        adminVerified: true,
      );
      expect(s, EchoStatus.verified);
    });
  });
}