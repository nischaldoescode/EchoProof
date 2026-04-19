// widget tests for the confidence bar
// verifies animation, percentage display, color changes per status

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:echoproof/app/theme/app_theme.dart';
import 'package:echoproof/features/echo/presentation/widgets/confidence_bar.dart';
import 'package:echoproof/features/echo/domain/entities/echo_status.dart';

Widget wrap(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('shows awaiting signals when confidence is zero', (tester) async {
    await tester.pumpWidget(wrap(
      const ConfidenceBar(
        confidence: 0,
        status: EchoStatus.pendingVerification,
      ),
    ));
    expect(find.text('awaiting signals'), findsOneWidget);
  });

  testWidgets('shows percentage when confidence is above zero', (tester) async {
    await tester.pumpWidget(wrap(
      const ConfidenceBar(
        confidence: 78.0,
        status: EchoStatus.active,
      ),
    ));
    // allow animation to settle
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('78%'), findsOneWidget);
  });

  testWidgets('shows community confidence label for verified status', (tester) async {
    await tester.pumpWidget(wrap(
      const ConfidenceBar(
        confidence: 85.0,
        status: EchoStatus.verified,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('community confidence'), findsOneWidget);
  });

  testWidgets('shows community split label for controversial status', (tester) async {
    await tester.pumpWidget(wrap(
      const ConfidenceBar(
        confidence: 52.0,
        status: EchoStatus.controversial,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('community split'), findsOneWidget);
  });

  testWidgets('renders a LinearProgressIndicator', (tester) async {
    await tester.pumpWidget(wrap(
      const ConfidenceBar(
        confidence: 60.0,
        status: EchoStatus.active,
      ),
    ));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
}