// layout regression checks for feed and profile surfaces
// these lock down paint order and empty state behavior that visual tests miss

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('created echoes are immediately handed back to the feed', () {
    final createService = File(
      'lib/features/echo/presentation/services/create_echo_service.dart',
    ).readAsStringSync();
    final createScreen = File(
      'lib/features/echo/presentation/screens/create_echo_screen.dart',
    ).readAsStringSync();
    final feedService = File(
      'lib/features/echo/presentation/services/echo_feed_service.dart',
    ).readAsStringSync();
    final feedScreen = File(
      'lib/features/echo/presentation/screens/feed_screen.dart',
    ).readAsStringSync();

    expect(createService, contains('EchoEntity? get lastCreatedEcho'));
    expect(createService, contains('EchoModel.fromRow(insertedRow'));
    expect(
      createScreen,
      contains('feedService.prependOwnCreatedEcho(createdEcho)'),
    );
    expect(
      feedService,
      contains('void prependOwnCreatedEcho(EchoEntity? echo)'),
    );
    expect(feedService, contains('_injectOwnRecentEchoes(decorated)'));
    expect(
      feedScreen,
      contains('void _handleOwnEchoInserted(EchoFeedService feed)'),
    );
    expect(feedScreen, contains('_lane = _FeedLane.forYou'));
    expect(feedScreen, contains('_filter = const FeedFilter()'));
  });

  test('feed ranker reserves a small author confirmation lane', () {
    final functionSource = File(
      '../../supabase/functions/personalized-feed/index.ts',
    ).readAsStringSync();
    final migrationSource = File(
      '../../supabase/migrations/20260701090000_feed_author_confirmation.sql',
    ).readAsStringSync();

    expect(functionSource, contains('const AUTHOR_CONFIRMATION_LIMIT = 2'));
    expect(functionSource, contains('const FRESH_DISCOVERY_LIMIT = 3'));
    expect(functionSource, contains('async function fetchAuthorRecent'));
    expect(functionSource, contains('async function fetchFreshDiscovery'));
    expect(functionSource, contains('freshDiscoveryScore'));
    expect(functionSource, contains('const authorFeedVersion'));
    expect(functionSource, contains('const freshDiscoveryVersion'));
    expect(functionSource, contains('feed:v7:'));
    expect(functionSource, contains('const reservedLaneIds'));
    expect(functionSource, contains('const rankedCapacity'));
    expect(migrationSource, contains('echoes_user_recent_feed_idx'));
    expect(
      migrationSource,
      contains(
        "when e.user_id = p_user_id and e.created_at > now() - interval '2 hours' then 95.0",
      ),
    );
    expect(
      migrationSource,
      contains(
        "when e.user_id <> p_user_id\n             and e.created_at > now() - interval '24 hours'",
      ),
    );
  });

  test('root feed navigation is free of forced ad surfaces', () {
    final navSource = File(
      'lib/shared/widgets/app_bottom_nav.dart',
    ).readAsStringSync();
    final feedSource = File(
      'lib/features/echo/presentation/screens/feed_screen.dart',
    ).readAsStringSync();
    final createSource = File(
      'lib/features/echo/presentation/screens/create_echo_screen.dart',
    ).readAsStringSync();
    final adServiceSource = File(
      'lib/core/services/ad_service.dart',
    ).readAsStringSync();
    final privacySource = File(
      '../../apps/echoproof-web/app/privacy/page.tsx',
    ).readAsStringSync();
    final termsSource = File(
      '../../apps/echoproof-web/app/terms/page.tsx',
    ).readAsStringSync();

    expect(navSource, isNot(contains('AppBannerAd')));
    expect(navSource, contains('root navigation stays ad-free'));
    expect(feedSource, isNot(contains('_feedAdTimer')));
    expect(feedSource, isNot(contains('showFeedRoutineAd')));
    expect(createSource, isNot(contains('showRewardedInterstitial')));
    expect(
      adServiceSource,
      contains(
        'callers should not use it from timers or while the user is reading',
      ),
    );
    expect(privacySource, contains('We use Sentry only for error tracking'));
    expect(
      termsSource,
      contains('We use Sentry only for background error tracking'),
    );
  });

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
