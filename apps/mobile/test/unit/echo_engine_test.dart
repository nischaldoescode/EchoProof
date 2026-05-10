// unit tests for echo engine scoring and decision logic
// pure dart — no flutter widgets, no db, no network

import 'package:flutter_test/flutter_test.dart';
import 'package:echoproof/core/engine/echo_engine_calculator.dart';
import 'package:echoproof/core/engine/echo_decision_engine.dart';
import 'package:echoproof/features/echo/domain/entities/echo_status.dart';

void main() {

  group('echo math engine — trust score', () {
    test('net positive support gives positive trust score', () {
      final result = EchoEngineCalculator.calculateEchoSnapshot(
        supportWeight: 15,
        challengeWeight: 5,
        supportCount: 3,
        challengeCount: 2,
        reportScore: 0,
        totalInteractions: 5,
      );
      expect(result.trustScore, 10);
    });

    test('more challenges than support gives negative trust score', () {
      final result = EchoEngineCalculator.calculateEchoSnapshot(
        supportWeight: 3,
        challengeWeight: 20,
        supportCount: 2,
        challengeCount: 8,
        reportScore: 0,
        totalInteractions: 10,
      );
      expect(result.trustScore, -17);
    });

    test('no interactions gives zero confidence', () {
      final result = EchoEngineCalculator.calculateEchoSnapshot(
        supportWeight: 0,
        challengeWeight: 0,
        supportCount: 0,
        challengeCount: 0,
        reportScore: 0,
        totalInteractions: 0,
      );
      expect(result.confidence, 0.0);
    });

    test('all support gives 100% confidence', () {
      final result = EchoEngineCalculator.calculateEchoSnapshot(
        supportWeight: 20,
        challengeWeight: 0,
        supportCount: 10,
        challengeCount: 0,
        reportScore: 0,
        totalInteractions: 10,
      );
      expect(result.confidence, 100.0);
    });

    test('equal split gives 50% confidence', () {
      final result = EchoEngineCalculator.calculateEchoSnapshot(
        supportWeight: 10,
        challengeWeight: 10,
        supportCount: 5,
        challengeCount: 5,
        reportScore: 0,
        totalInteractions: 10,
      );
      expect(result.confidence, 50.0);
    });
  });

  group('echo decision engine — status', () {
    test('report score >= 70 forces hidden regardless of support', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: 100,
        confidence: 95,
        controversy: 0.0,
        reportScore: 80,
        totalInteractions: 100,
      );
      expect(status, EchoStatus.hidden);
    });

    test('high trust and confidence marks as verified', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: 55,
        confidence: 75,
        controversy: 0.1,
        reportScore: 0,
        totalInteractions: 60,
      );
      expect(status, EchoStatus.verified);
    });

    test('balanced split with >= 10 interactions marks as controversial', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: 2,
        confidence: 52,
        controversy: 0.85,
        reportScore: 5,
        totalInteractions: 40,
      );
      expect(status, EchoStatus.controversial);
    });

    test('negative trust score marks as disputed', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: -15,
        confidence: 20,
        controversy: 0.2,
        reportScore: 5,
        totalInteractions: 20,
      );
      expect(status, EchoStatus.disputed);
    });

    test('zero interactions gives pendingVerification', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: 0,
        confidence: 0,
        controversy: 0,
        reportScore: 0,
        totalInteractions: 0,
      );
      expect(status, EchoStatus.pendingVerification);
    });

    test('admin override true forces verified even with bad scores', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: -100,
        confidence: 10,
        controversy: 0.9,
        reportScore: 0,
        totalInteractions: 50,
        adminVerified: true,
      );
      expect(status, EchoStatus.verified);
    });

    test('admin override false forces rejected', () {
      final status = EchoDecisionEngine.determineStatus(
        trustScore: 100,
        confidence: 99,
        controversy: 0.0,
        reportScore: 0,
        totalInteractions: 200,
        adminVerified: false,
      );
      expect(status, EchoStatus.rejected);
    });
  });
}