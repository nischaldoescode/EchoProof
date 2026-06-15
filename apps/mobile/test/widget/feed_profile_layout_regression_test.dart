// layout regression checks for feed and profile surfaces
// these lock down paint order and empty state behavior that visual tests miss

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feed reply thread is owned by avatar lanes', () {
    final source = File(
      'lib/features/echo/presentation/screens/feed_screen.dart',
    ).readAsStringSync();
    final cardState = source.indexOf('class _AnimatedCardState');
    expect(cardState, isNonNegative);

    final card = source.indexOf('EchoCard(', cardState);
    final tail = source.indexOf('showThreadTail: hasThread', card);
    final reply = source.indexOf('EchoReplyPreviewCard(', tail);

    expect(card, isNonNegative);
    expect(tail, isNonNegative);
    expect(reply, isNonNegative);
    expect(reply, greaterThan(tail));
    expect(source, isNot(contains('class _FeedThreadLine')));

    final cardSource = File(
      'lib/features/echo/presentation/widgets/echo_card.dart',
    ).readAsStringSync();
    expect(cardSource, contains('clipBehavior: Clip.none'));
    expect(cardSource, contains('top: -7'));
    expect(cardSource, contains('return IntrinsicHeight('));
  });

  test('profile empty tabs are states and not scrollable feed bodies', () {
    final source = File(
      'lib/features/profile/presentation/screens/profile_screen.dart',
    ).readAsStringSync();
    final bodyStart = source.indexOf('Widget _buildBody()');
    final bodyEnd = source.indexOf('void _openFollowList', bodyStart);
    expect(bodyStart, isNonNegative);
    expect(bodyEnd, isNonNegative);
    final bodySource = source.substring(bodyStart, bodyEnd);

    expect(bodySource, contains('TabBar('));
    expect(bodySource, contains('controller: profileTabController'));
    expect(bodySource, contains('CustomScrollView('));
    expect(bodySource, contains('_ProfileTabBodyStack('));
    expect(bodySource, isNot(contains('TabBarView(')));
    expect(bodySource, isNot(contains('NestedScrollView(')));
    expect(bodySource, contains('physics: const ClampingScrollPhysics()'));
    expect(bodySource, contains('_profileOuterScrollController'));
    expect(bodySource, contains('controller: _profileOuterScrollController'));
    expect(source, contains('_lastProfileTabIndex == controller.index'));
    expect(source, contains('class _ProfileTabBodyStack'));
    expect(source, contains('Offstage('));
    expect(source, contains('TickerMode('));
    expect(
      source,
      contains('visited tabs stay alive but only the selected tab takes space'),
    );
    expect(source, contains('class _ProfileEmptyStateBody'));
    expect(source, contains("storageKey: 'profile-empty-echoes'"));
    expect(source, contains("storageKey: 'profile-empty-replies'"));
    expect(source, contains("storageKey: 'profile-empty-media'"));
    expect(source, contains('physics: const NeverScrollableScrollPhysics()'));
    expect(source, contains('shrinkWrap: true'));

    final emptyStart = source.indexOf('class _ProfileEmptyStateBody');
    final emptyEnd = source.indexOf('class _LockedProfileTab', emptyStart);
    final emptyTabSource = source.substring(emptyStart, emptyEnd);
    expect(emptyTabSource, contains('KeyedSubtree'));
    expect(emptyTabSource, contains('ColoredBox'));
    expect(emptyTabSource, isNot(contains('CustomScrollView')));
    expect(emptyTabSource, isNot(contains('NeverScrollableScrollPhysics')));
  });
}
