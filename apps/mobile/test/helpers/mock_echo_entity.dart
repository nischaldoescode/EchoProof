// test helper — mock echo entity factory
// used by echo_card_test.dart and any future widget tests

import 'package:mocktail/mocktail.dart';
import 'package:echoproof/features/echo/domain/entities/echo_entity.dart';
import 'package:echoproof/features/echo/domain/entities/echo_status.dart';

class MockEchoEntity extends Mock implements EchoEntity {}

// factory that builds a fully stubbed MockEchoEntity for widget tests
MockEchoEntity makeMockEcho({
  EchoStatus status = EchoStatus.active,
  double confidence = 65.0,
}) {
  final mock = MockEchoEntity();

  when(() => mock.id).thenReturn('test-id');
  when(() => mock.title).thenReturn('This is a test echo title');
  when(() => mock.content).thenReturn(
    'This is the content of the echo for testing purposes.',
  );
  when(() => mock.username).thenReturn('anonymous_user_42');
  when(() => mock.userTrustTier).thenReturn('medium');
  when(() => mock.userIsVerified).thenReturn(true);
  when(() => mock.userAvatarUrl).thenReturn(null);
  when(() => mock.category).thenReturn(EchoCategory.tech);
  when(() => mock.status).thenReturn(status);
  when(() => mock.confidenceScore).thenReturn(confidence);
  when(() => mock.trustScore).thenReturn(30);
  when(() => mock.controversyScore).thenReturn(0.2);
  when(() => mock.supportCount).thenReturn(80);
  when(() => mock.challengeCount).thenReturn(20);
  when(() => mock.timeAgo).thenReturn('2h ago');
  when(() => mock.proofCount).thenReturn(0);
  when(() => mock.requiresVerification).thenReturn(true);

  return mock;
}
