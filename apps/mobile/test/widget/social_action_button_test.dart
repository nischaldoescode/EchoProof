import 'package:echoproof/shared/widgets/social_action_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('social action toggles without overshooting curves', (
    tester,
  ) async {
    var active = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Center(
                child: SocialActionButton(
                  icon: Icons.favorite_border_rounded,
                  activeIcon: Icons.favorite_rounded,
                  label: active ? '1' : '',
                  active: active,
                  showBurst: true,
                  onTap: () => setState(() => active = !active),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byType(SocialActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(SocialActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.takeException(), isNull);
  });
}
