// widget tests for mention suggestion presentation
// keeps the composer popup compact on large and split-screen surfaces

import 'dart:io';

import 'package:echoproof/app/theme/app_theme.dart';
import 'package:echoproof/shared/widgets/mention_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mentions/flutter_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mention suggestion portal stays compact on wide screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mentionKey = GlobalKey<FlutterMentionsState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Portal(
            child: Scaffold(
              body: CompactMentionSuggestions(
                visible: true,
                position: SuggestionPosition.Bottom,
                suggestionHeight: 190,
                mentionKey: mentionKey,
                suggestions: const [
                  {
                    'id': 'user-1',
                    'display': 'peytonlist',
                    'name': 'Peyton List',
                    'avatar_url': '',
                    'trust_tier': 'high',
                    '_suggestion_index': 0,
                    '_suggestion_count': 1,
                  },
                ],
                child: const SizedBox(width: 800, height: 48),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    final panel = find.byKey(const ValueKey('mention_suggestion_panel'));
    expect(tester.getSize(panel).width, lessThanOrEqualTo(480));
    expect(find.text('Peyton List'), findsOneWidget);
    expect(find.text('@peytonlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mention suggestion portal respects split-screen width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mentionKey = GlobalKey<FlutterMentionsState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 520)),
          child: Portal(
            child: Scaffold(
              body: CompactMentionSuggestions(
                visible: true,
                position: SuggestionPosition.Bottom,
                suggestionHeight: 190,
                mentionKey: mentionKey,
                suggestions: const [
                  {
                    'id': 'user-2',
                    'display': 'very_long_username_that_must_ellipsis',
                    'name': 'Very Long Display Name That Must Ellipsis',
                    'avatar_url': '',
                    'trust_tier': 'unverified',
                    '_suggestion_index': 0,
                    '_suggestion_count': 1,
                  },
                ],
                child: const SizedBox(width: 320, height: 48),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    final panel = find.byKey(const ValueKey('mention_suggestion_panel'));
    expect(tester.getSize(panel).width, lessThanOrEqualTo(296));
    expect(tester.takeException(), isNull);
  });

  testWidgets('forced mention suggestions open above bottom composers', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final anchorKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(420, 720)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 72),
                child: SizedBox(key: anchorKey, width: 300, height: 48),
              ),
            ),
          ),
        ),
      ),
    );

    final natural = adaptiveMentionSuggestionPosition(
      anchorKey.currentContext!,
      listHeight: 190,
      preferTopWhenCrowded: true,
    );
    final forced = adaptiveMentionSuggestionPosition(
      anchorKey.currentContext!,
      listHeight: 220,
      preferTopWhenCrowded: true,
      forceTop: true,
    );

    expect(natural, SuggestionPosition.Top);
    expect(forced, SuggestionPosition.Top);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mention suggestion portal stays inside narrow right anchor', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mentionKey = GlobalKey<FlutterMentionsState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: Portal(
            child: Scaffold(
              body: Align(
                alignment: Alignment.topRight,
                child: CompactMentionSuggestions(
                  visible: true,
                  position: SuggestionPosition.Bottom,
                  suggestionHeight: 190,
                  mentionKey: mentionKey,
                  suggestions: const [
                    {
                      'id': 'user-4',
                      'display': 'rightedge',
                      'name': 'Right Edge',
                      'avatar_url': '',
                      'trust_tier': 'high',
                      '_suggestion_index': 0,
                      '_suggestion_count': 1,
                    },
                  ],
                  child: const SizedBox(width: 180, height: 48),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    final panel = find.byKey(const ValueKey('mention_suggestion_panel'));
    final rect = tester.getRect(panel);
    expect(rect.width, lessThanOrEqualTo(180));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mention suggestion tap inserts through flutter mentions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(520, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mentionKey = GlobalKey<FlutterMentionsState>();
    var search = '';
    var visible = false;
    final users = <Map<String, dynamic>>[
      {
        'id': 'user-3',
        'display': 'peytonlist',
        'name': 'Peyton List',
        'avatar_url': '',
        'trust_tier': 'high',
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(520, 640)),
          child: Portal(
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  final suggestions = visibleMentionUsers(search, users);
                  return CompactMentionSuggestions(
                    visible: visible,
                    position: SuggestionPosition.Bottom,
                    suggestionHeight: 190,
                    suggestions: suggestions,
                    mentionKey: mentionKey,
                    onSelected: (_) => setState(() {
                      visible = false;
                      search = '';
                    }),
                    child: FlutterMentions(
                      key: mentionKey,
                      hideSuggestionList: true,
                      onSuggestionVisibleChanged: (value) =>
                          setState(() => visible = value),
                      onSearchChanged: (trigger, value) {
                        if (trigger != '@') return;
                        setState(() => search = value);
                      },
                      mentions: [
                        Mention(
                          trigger: '@',
                          data: users,
                          suggestionBuilder: (data) =>
                              MentionSuggestionTile(data: data),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '@pey');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('mention_suggestion_panel')), findsOne);

    await tester.tap(find.text('Peyton List'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(mentionKey.currentState?.controller?.text, '@peytonlist ');
    expect(
      find.byKey(const ValueKey('mention_suggestion_panel')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('create echo closes mention portal before draft sheet', () {
    final source = File(
      'lib/features/echo/presentation/screens/create_echo_screen.dart',
    ).readAsStringSync();

    expect(source, contains('Future<void> _dismissComposerOverlays()'));
    expect(source, contains('hideMentionSuggestions(_contentKey)'));
    expect(source, contains('FocusManager.instance.primaryFocus?.unfocus()'));
    expect(source, contains('await WidgetsBinding.instance.endOfFrame'));
    expect(source, contains('hideSuggestionList: true'));
  });

  test('reply composer uses upward compact mention suggestions', () {
    final source = File(
      'lib/features/echo/presentation/screens/echo_replies_screen.dart',
    ).readAsStringSync();
    final replyInputStart = source.indexOf('class _ReplyInputState');
    expect(replyInputStart, isNonNegative);
    final replyInputEnd = source.indexOf(
      'class _VerifiedAvatar',
      replyInputStart,
    );
    expect(replyInputEnd, isNonNegative);
    final replyInputSource = source.substring(replyInputStart, replyInputEnd);

    expect(replyInputSource, contains('CompactMentionSuggestions'));
    expect(replyInputSource, contains('listHeight: 220'));
    expect(replyInputSource, contains('maxHeight: 220'));
    expect(replyInputSource, contains('forceTop: true'));
    expect(replyInputSource, contains('hideSuggestionList: true'));
  });

  test('login agreement and email field keep stable layout metrics', () {
    final source = File(
      'lib/features/auth/presentation/screens/login_screen.dart',
    ).readAsStringSync();

    expect(source, contains('width: 1.3'));
    expect(source, isNot(contains('width: _focused ? 1.6 : 1.2')));
    expect(source, isNot(contains('AnimatedScale')));
    expect(source, contains('width: 30'));
    expect(source, contains('height: 30'));
    expect(source, contains('width: 22'));
    expect(source, contains('height: 22'));
    expect(source, contains('Alignment.topCenter'));
    expect(source, contains('class _LoginEntranceItem'));
    expect(source, contains('start: hasPendingDeepLink ? 0.10 : 0.00'));
    expect(source, contains('scale: 0.985 + curved * 0.015'));
  });
}
