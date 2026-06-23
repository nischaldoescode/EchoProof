// widget tests for app motion surfaces
// keeps swipe cancellation and compact onboarding layout from regressing

import 'dart:io';

import 'package:echoproof/app/theme/app_theme.dart';
import 'package:echoproof/features/onboarding/presentation/widgets/onboarding_story_frame.dart';
import 'package:echoproof/shared/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('root swipe wrapper settles cancelled drags without exceptions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const SwipeNavigationWrapper(
          currentLocation: '/discover',
          child: Scaffold(body: Center(child: Text('root screen'))),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('root screen')),
    );
    await gesture.moveBy(const Offset(84, 0));
    await tester.pump();
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    final maxHorizontalOffset = transforms.fold<double>(0, (maxOffset, t) {
      final x = t.transform.storage[12].abs();
      return x > maxOffset ? x : maxOffset;
    });
    expect(maxHorizontalOffset, lessThanOrEqualTo(20));

    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 220));

    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding story frame fits compact split-screen height', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: OnboardingStoryFrame(
          currentStep: 1,
          totalSteps: 7,
          title: 'story title',
          body: 'short body that can wrap on compact screens',
          sceneIcon: Icons.shield_outlined,
          sceneLabel: 'compact scene label',
          footer: ElevatedButton(onPressed: () {}, child: const Text('next')),
          children: const [
            Text('content row'),
            SizedBox(height: 12),
            Text('another compact row'),
          ],
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 450));

    expect(tester.takeException(), isNull);
    expect(find.text('story title'), findsOneWidget);
    expect(find.text('next'), findsOneWidget);
  });

  test('discover defaults to india and keeps manual country scope', () {
    final source = File(
      'lib/features/echo/presentation/screens/discover_screen.dart',
    ).readAsStringSync();

    expect(source, contains("static const String _defaultCountryCode = 'IN'"));
    expect(source, contains('static bool _hasStoredCountryChoice = false'));
    expect(source, contains('? _lastSelectedCountry'));
    expect(source, contains(': _defaultCountryCode'));
    expect(source, contains('_hasStoredCountryChoice = true'));
    expect(source, contains('_lastSelectedCountry = code'));
    expect(source, isNot(contains('IpHunter')));
    expect(source, isNot(contains('_detectCountryAndLoad')));
    expect(source, isNot(contains('_entranceController')));
  });
}
