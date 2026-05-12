// widget tests for echo card
// verifies rendering, status labels, confidence display
// uses mocktail mocks — no supabase connection needed

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:echoproof/app/theme/app_theme.dart';
import 'package:echoproof/features/echo/domain/entities/echo_status.dart';
import 'package:echoproof/features/echo/presentation/widgets/echo_card.dart';
import 'package:echoproof/features/echo/presentation/services/echo_feed_service.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../helpers/mock_echo_entity.dart';

// wraps widget in app theme + provider for EchoFeedService
// echo_card uses EchoFeedService via context for interaction buttons
Widget wrapWithApp(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => EchoFeedService(),
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets('renders title and content correctly', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(EchoCard(echo: makeMockEcho())),
    );
    expect(find.text('This is a test echo title'), findsOneWidget);
    expect(find.textContaining('content of the echo'), findsOneWidget);
  });

  testWidgets('verified status shows verified label', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        EchoCard(
          echo: makeMockEcho(
            status: EchoStatus.verified,
            confidence: 82,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Verified by community'), findsOneWidget);
  });

  testWidgets('disputed status shows disputed label', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        EchoCard(
          echo: makeMockEcho(
            status: EchoStatus.disputed,
            confidence: 22,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Disputed'), findsOneWidget);
  });

  testWidgets('controversial status shows split label', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        EchoCard(
          echo: makeMockEcho(
            status: EchoStatus.controversial,
            confidence: 51,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Controversial'), findsOneWidget);
  });

  testWidgets('confidence bar shows correct percentage', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        EchoCard(echo: makeMockEcho(confidence: 75.0)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('75%'), findsOneWidget);
  });

  testWidgets('zero confidence shows awaiting signals', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        EchoCard(
          echo: makeMockEcho(
            status: EchoStatus.pendingVerification,
            confidence: 0,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('awaiting signals'), findsOneWidget);
  });
}
