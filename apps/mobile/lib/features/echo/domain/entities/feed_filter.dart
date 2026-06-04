// feed filter
// @params none

import 'echo_status.dart';
import 'echo_entity.dart';

class FeedFilter {
  const FeedFilter({
    this.statuses = const {},
    this.categories = const {},
    this.sortBy = FeedSortBy.trending,
    this.showVerifiedOnly = false,
    this.showUnverifiedOnly = false,
    this.minTrustScore,
    this.maxTrustScore,
  });

  final Set<EchoStatus> statuses;
  final Set<EchoCategory> categories;
  final FeedSortBy sortBy;
  final bool showVerifiedOnly;
  final bool showUnverifiedOnly;
  final int? minTrustScore;
  final int? maxTrustScore;

  bool get isActive =>
      statuses.isNotEmpty ||
      categories.isNotEmpty ||
      showVerifiedOnly ||
      showUnverifiedOnly ||
      minTrustScore != null ||
      sortBy != FeedSortBy.trending;

  FeedFilter copyWith({
    Set<EchoStatus>? statuses,
    Set<EchoCategory>? categories,
    FeedSortBy? sortBy,
    bool? showVerifiedOnly,
    bool? showUnverifiedOnly,
    int? minTrustScore,
    int? maxTrustScore,
    bool clearMinTrust = false,
  }) {
    return FeedFilter(
      statuses: statuses ?? this.statuses,
      categories: categories ?? this.categories,
      sortBy: sortBy ?? this.sortBy,
      showVerifiedOnly: showVerifiedOnly ?? this.showVerifiedOnly,
      showUnverifiedOnly: showUnverifiedOnly ?? this.showUnverifiedOnly,
      minTrustScore:
          clearMinTrust ? null : (minTrustScore ?? this.minTrustScore),
    );
  }

  List<EchoEntity> apply(List<EchoEntity> echoes) {
    var result = echoes.where((e) {
      if (showVerifiedOnly && e.status != EchoStatus.verified) return false;
      if (showUnverifiedOnly && e.status == EchoStatus.verified) return false;
      if (statuses.isNotEmpty && !statuses.contains(e.status)) return false;
      if (categories.isNotEmpty && !categories.contains(e.category))
        return false;
      if (minTrustScore != null && e.trustScore < minTrustScore!) return false;
      return true;
    }).toList();

    result.sort((a, b) => switch (sortBy) {
          FeedSortBy.trending => b.trustScore.compareTo(a.trustScore),
          FeedSortBy.newest => b.timeAgo.compareTo(a.timeAgo),
          FeedSortBy.mostSupport => b.supportCount.compareTo(a.supportCount),
          FeedSortBy.mostDebated =>
            b.challengeCount.compareTo(a.challengeCount),
          FeedSortBy.confidence =>
            b.confidenceScore.compareTo(a.confidenceScore),
        });

    return result;
  }
}

enum FeedSortBy {
  trending,
  newest,
  mostSupport,
  mostDebated,
  confidence;

  String get label => switch (this) {
        FeedSortBy.trending => 'Trending',
        FeedSortBy.newest => 'Newest',
        FeedSortBy.mostSupport => 'Most support',
        FeedSortBy.mostDebated => 'Most debated',
        FeedSortBy.confidence => 'Most confident',
      };
}
