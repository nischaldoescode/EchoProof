import 'package:echoproof/features/echo/presentation/widgets/link_preview_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget previewHost(Widget child) {
    return MaterialApp(
      home: Scaffold(body: SizedBox(width: 380, child: child)),
    );
  }

  testWidgets('uses the published metadata snapshot without fetching', (
    tester,
  ) async {
    await tester.pumpWidget(
      previewHost(
        const EchoLinkPreview(
          url: 'https://example.com/source',
          fetchWhenMetadataMissing: false,
          metadata: {
            'title': 'published source title',
            'description': 'published source description',
            'site_name': 'example source',
          },
        ),
      ),
    );

    await tester.pump();

    expect(find.text('published source title'), findsOneWidget);
    expect(find.text('published source description'), findsOneWidget);
    expect(find.text('EXAMPLE SOURCE'), findsOneWidget);
    expect(find.text('Loading preview...'), findsNothing);
  });

  testWidgets('keeps a stable generic source card without metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      previewHost(
        const EchoLinkPreview(
          url: 'https://example.com/source',
          fetchWhenMetadataMissing: false,
        ),
      ),
    );

    await tester.pump();

    expect(find.text('EXAMPLE.COM'), findsOneWidget);
    expect(find.text('https://example.com/source'), findsOneWidget);
    expect(find.text('Loading preview...'), findsNothing);
  });
}
