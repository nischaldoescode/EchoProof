// integration test for the authentication flow
// requires: supabase local running
// requires: integration_test sdk in pubspec.yaml dev_dependencies
// run with: flutter test test/integration/auth_flow_test.dart -d DEVICE_ID

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:echoproof/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('auth flow', () {
    testWidgets('login screen renders after splash', (tester) async {
      app.main();
      // wait for splash animation and navigation
      await tester.pumpAndSettle(const Duration(seconds: 4));
      // login screen should show echoproof title
      expect(find.text('Echoproof'), findsWidgets);
    });

    testWidgets('empty form shows validation errors', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // tap sign in without filling anything
      final buttons = find.text('Sign in');
      if (buttons.evaluate().isNotEmpty) {
        await tester.tap(buttons.last);
        await tester.pumpAndSettle();
        expect(find.text('email is required'), findsOneWidget);
      }
    });

    testWidgets('invalid email shows format error', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final emailFields = find.byType(TextFormField);
      if (emailFields.evaluate().isNotEmpty) {
        await tester.enterText(emailFields.first, 'notanemail');
        final buttons = find.text('Sign in');
        if (buttons.evaluate().isNotEmpty) {
          await tester.tap(buttons.last);
          await tester.pumpAndSettle();
          expect(find.text('enter a valid email'), findsOneWidget);
        }
      }
    });
  });
}
