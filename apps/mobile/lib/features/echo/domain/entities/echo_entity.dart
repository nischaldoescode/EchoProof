// echo entity pure domain model, no flutter or supabase dependencies
// immutable value object using freezed pattern (manual here, add freezed later)
// this is what the ui layer works with never raw db maps

import 'package:equatable/equatable.dart';
import 'echo_status.dart';

/// category of an echo matches the sql echo_category enum exactly
enum EchoCategory {
  tech,
  finance,
  startups,
  socialIssues,
  web3,
  ai,
  gaming,
  education,
  other;

  String get displayName => switch (this) {
    EchoCategory.tech => 'Tech',
    EchoCategory.finance => 'Finance',
    EchoCategory.startups => 'Startups',
    EchoCategory.socialIssues => 'Social Issues',
    EchoCategory.web3 => 'Web3',
    EchoCategory.ai => 'AI',
    EchoCategory.gaming => 'Gaming',
    EchoCategory.education => 'Education',
    EchoCategory.other => 'Other',
  };

  String get dbValue => switch (this) {
    EchoCategory.socialIssues => 'social_issues',
    _ => name,
  };

  /// maps db string value to enum
  static EchoCategory fromString(String value) => switch (value) {
    'tech' => EchoCategory.tech,
    'finance' => EchoCategory.finance,
    'startups' => EchoCategory.startups,
    'social_issues' => EchoCategory.socialIssues,
    'web3' => EchoCategory.web3,
    'ai' => EchoCategory.ai,
    'gaming' => EchoCategory.gaming,
    'education' => EchoCategory.education,
    _ => EchoCategory.other,
  };
}

/// trust tier matches sql trust_tier enum
enum TrustTier {
  unverified,
  low,
  medium,
  high,
  elite;

  static TrustTier fromString(String value) => switch (value) {
    'low' => TrustTier.low,
    'medium' => TrustTier.medium,
    'high' => TrustTier.high,
    'elite' => TrustTier.elite,
    _ => TrustTier.unverified,
  };

  String get displayLabel => switch (this) {
    TrustTier.unverified => 'Unverified',
    TrustTier.low => 'Low',
    TrustTier.medium => 'Medium',
    TrustTier.high => 'High',
    TrustTier.elite => 'Elite',
  };

  /// interaction weight this tier contributes
  int get weight => switch (this) {
    TrustTier.elite => 5,
    TrustTier.high => 4,
    TrustTier.medium => 3,
    TrustTier.low => 2,
    TrustTier.unverified => 1,
  };
}

/// the core domain entity representing a single echo (post)
/// all fields are immutable use copywith to produce updated versions
class EchoEntity extends Equatable {
  const EchoEntity({
    required this.id,
    required this.title,
    required this.content,
    required this.username,
    required this.userDisplayName,
    required this.userTrustTier,
    required this.userIsVerified,
    required this.userAvatarUrl,
    required this.category,
    required this.status,
    required this.confidenceScore,
    required this.trustScore,
    required this.controversyScore,
    required this.supportCount,
    required this.challengeCount,
    required this.timeAgo,
    required this.userIsPro,
    this.proofCount = 0,
    this.requiresVerification = true,
    this.version = 1,
    this.replyCount = 0,
    this.viewCount = 0,
    this.mediaUrls = const [],
    this.categoryDetail,
    this.userId = '',
    this.createdRecordTx,
    this.createdRecordAt,
    this.solanaStatus = 'pending',
    this.solanaError,
    this.verifiedRecordTx,
    this.verifiedRecordAt,
    this.verifiedRecordStatus = 'pending',
    this.verifiedRecordError,
    this.bondCount = 0,
    this.socialContext,
    this.publicVerdict = 'open',
    this.publicVerdictAt,
    this.publicContextClosesAt,
    this.publicContextMinCount = 7,
    this.publicContextDecisionReason,
    this.contextScore = 0,
    this.contextSupportCount = 0,
    this.contextChallengeCount = 0,
    this.topContext,
    this.previewReplies = const [],
  });

  final String id;
  final String title;
  final String content;
  final String username;
  final String userDisplayName;
  final String userTrustTier;
  final bool userIsVerified;
  final String? userAvatarUrl;
  final EchoCategory category;
  final String? categoryDetail;
  final EchoStatus status;
  final bool userIsPro;

  /// 0.0 to 100.0 percentage of weighted support
  final double confidenceScore;
  final List<String> mediaUrls;

  /// net weighted score = support_weight - challenge_weight
  final int trustScore;
  final int version;

  /// 0.0 to 100.0 how balanced the split is
  final double controversyScore;

  final int supportCount;
  final int challengeCount;
  final int replyCount;
  final int viewCount;
  final String userId;
  final String? createdRecordTx;
  final DateTime? createdRecordAt;
  final String solanaStatus;
  final String? solanaError;
  final String? verifiedRecordTx;
  final DateTime? verifiedRecordAt;
  final String verifiedRecordStatus;
  final String? verifiedRecordError;
  final int bondCount;
  final String? socialContext;
  final String publicVerdict;
  final DateTime? publicVerdictAt;
  final DateTime? publicContextClosesAt;
  final int publicContextMinCount;
  final String? publicContextDecisionReason;
  final int contextScore;
  final int contextSupportCount;
  final int contextChallengeCount;
  final EchoContextPreview? topContext;
  final List<EchoReplyPreview> previewReplies;

  /// pre-formatted relative time string, e.g. "2h ago"
  final String timeAgo;

  final int proofCount;
  final bool requiresVerification;

  factory EchoEntity.fromJson(Map<String, dynamic> json) {
    return EchoEntity(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      username: json['username'] as String,
      userDisplayName:
          json['user_display_name'] as String? ?? json['username'] as String,
      userTrustTier: json['user_trust_tier'] as String,
      userIsVerified: json['user_is_verified'] as bool,
      userAvatarUrl: json['user_avatar_url'] as String?,
      category: EchoCategory.fromString(json['category'] as String),
      categoryDetail: json['category_detail'] as String?,
      status: EchoStatus.fromString(json['status'] as String),
      confidenceScore: (json['confidence_score'] as num).toDouble(),
      trustScore: json['trust_score'] as int,
      controversyScore: (json['controversy_score'] as num).toDouble(),
      supportCount:
          ((json['context_support_count'] as num?) ??
                  (json['support_count'] as num?))
              ?.toInt() ??
          0,
      challengeCount:
          ((json['context_challenge_count'] as num?) ??
                  (json['challenge_count'] as num?))
              ?.toInt() ??
          0,
      timeAgo: json['time_ago'] as String,
      proofCount: (json['proof_count'] as int?) ?? 0,
      requiresVerification: (json['requires_verification'] as bool?) ?? true,
      version: (json['version'] as num?)?.toInt() ?? 1,
      userIsPro: (json['user_is_pro'] as bool?) ?? false,
      mediaUrls: (json['media_urls'] as List?)?.cast<String>() ?? const [],
      replyCount: (json['reply_count'] as int?) ?? 0,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      userId: json['user_id'] as String? ?? '',
      createdRecordTx: json['created_record_tx'] as String?,
      createdRecordAt: _dateFromJson(json['created_record_at']),
      solanaStatus: json['solana_status'] as String? ?? 'pending',
      solanaError: json['solana_error'] as String?,
      verifiedRecordTx: json['verified_record_tx'] as String?,
      verifiedRecordAt: _dateFromJson(json['verified_record_at']),
      verifiedRecordStatus:
          json['verified_record_status'] as String? ?? 'pending',
      verifiedRecordError: json['verified_record_error'] as String?,
      bondCount: (json['bond_count'] as num?)?.toInt() ?? 0,
      socialContext: json['social_context'] as String?,
      publicVerdict: json['public_verdict'] as String? ?? 'open',
      publicVerdictAt: _dateFromJson(json['public_verdict_at']),
      publicContextClosesAt: _dateFromJson(json['public_context_closes_at']),
      publicContextMinCount:
          (json['public_context_min_count'] as num?)?.toInt() ?? 7,
      publicContextDecisionReason:
          json['public_context_decision_reason'] as String?,
      contextScore: (json['context_score'] as num?)?.toInt() ?? 0,
      contextSupportCount:
          (json['context_support_count'] as num?)?.toInt() ?? 0,
      contextChallengeCount:
          (json['context_challenge_count'] as num?)?.toInt() ?? 0,
      topContext: json['top_context'] is Map<String, dynamic>
          ? EchoContextPreview.fromJson(
              json['top_context'] as Map<String, dynamic>,
            )
          : null,
      previewReplies:
          (json['preview_replies'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(EchoReplyPreview.fromJson)
              .toList() ??
          const [],
    );
  }

  static DateTime? _dateFromJson(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  EchoEntity copyWith({
    String? id,
    String? title,
    String? content,
    String? username,
    String? userDisplayName,
    String? userTrustTier,
    bool? userIsVerified,
    String? userAvatarUrl,
    EchoCategory? category,
    String? categoryDetail,
    EchoStatus? status,
    double? confidenceScore,
    int? trustScore,
    double? controversyScore,
    int? supportCount,
    int? challengeCount,
    String? timeAgo,
    int? proofCount,
    bool? requiresVerification,
    int? version,
    int? replyCount,
    int? viewCount,
    bool? userIsPro,
    List<String>? mediaUrls,
    String? userId,
    String? createdRecordTx,
    DateTime? createdRecordAt,
    String? solanaStatus,
    String? solanaError,
    String? verifiedRecordTx,
    DateTime? verifiedRecordAt,
    String? verifiedRecordStatus,
    String? verifiedRecordError,
    int? bondCount,
    String? socialContext,
    String? publicVerdict,
    DateTime? publicVerdictAt,
    DateTime? publicContextClosesAt,
    int? publicContextMinCount,
    String? publicContextDecisionReason,
    int? contextScore,
    int? contextSupportCount,
    int? contextChallengeCount,
    EchoContextPreview? topContext,
    List<EchoReplyPreview>? previewReplies,
  }) {
    return EchoEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      username: username ?? this.username,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userTrustTier: userTrustTier ?? this.userTrustTier,
      userIsVerified: userIsVerified ?? this.userIsVerified,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      category: category ?? this.category,
      categoryDetail: categoryDetail ?? this.categoryDetail,
      status: status ?? this.status,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      trustScore: trustScore ?? this.trustScore,
      controversyScore: controversyScore ?? this.controversyScore,
      supportCount: supportCount ?? this.supportCount,
      challengeCount: challengeCount ?? this.challengeCount,
      replyCount: replyCount ?? this.replyCount,
      timeAgo: timeAgo ?? this.timeAgo,
      proofCount: proofCount ?? this.proofCount,
      requiresVerification: requiresVerification ?? this.requiresVerification,
      version: version ?? this.version,
      userIsPro: userIsPro ?? this.userIsPro,
      viewCount: viewCount ?? this.viewCount,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      userId: userId ?? this.userId,
      createdRecordTx: createdRecordTx ?? this.createdRecordTx,
      createdRecordAt: createdRecordAt ?? this.createdRecordAt,
      solanaStatus: solanaStatus ?? this.solanaStatus,
      solanaError: solanaError ?? this.solanaError,
      verifiedRecordTx: verifiedRecordTx ?? this.verifiedRecordTx,
      verifiedRecordAt: verifiedRecordAt ?? this.verifiedRecordAt,
      verifiedRecordStatus: verifiedRecordStatus ?? this.verifiedRecordStatus,
      verifiedRecordError: verifiedRecordError ?? this.verifiedRecordError,
      bondCount: bondCount ?? this.bondCount,
      socialContext: socialContext ?? this.socialContext,
      publicVerdict: publicVerdict ?? this.publicVerdict,
      publicVerdictAt: publicVerdictAt ?? this.publicVerdictAt,
      publicContextClosesAt:
          publicContextClosesAt ?? this.publicContextClosesAt,
      publicContextMinCount:
          publicContextMinCount ?? this.publicContextMinCount,
      publicContextDecisionReason:
          publicContextDecisionReason ?? this.publicContextDecisionReason,
      contextScore: contextScore ?? this.contextScore,
      contextSupportCount: contextSupportCount ?? this.contextSupportCount,
      contextChallengeCount:
          contextChallengeCount ?? this.contextChallengeCount,
      topContext: topContext ?? this.topContext,
      previewReplies: previewReplies ?? this.previewReplies,
    );
  }

  @override
  List<Object?> get props => [
    id,
    title,
    content,
    username,
    userDisplayName,
    userTrustTier,
    userIsVerified,
    userAvatarUrl,
    category,
    categoryDetail,
    status,
    confidenceScore,
    trustScore,
    controversyScore,
    supportCount,
    challengeCount,
    timeAgo,
    proofCount,
    requiresVerification,
    version,
    replyCount,
    viewCount,
    userId,
    userIsPro,
    mediaUrls,
    createdRecordTx,
    createdRecordAt,
    solanaStatus,
    solanaError,
    verifiedRecordTx,
    verifiedRecordAt,
    verifiedRecordStatus,
    verifiedRecordError,
    bondCount,
    socialContext,
    publicVerdict,
    publicVerdictAt,
    publicContextClosesAt,
    publicContextMinCount,
    publicContextDecisionReason,
    contextScore,
    contextSupportCount,
    contextChallengeCount,
    topContext,
    previewReplies,
  ];
}

class EchoContextPreview extends Equatable {
  const EchoContextPreview({
    required this.id,
    required this.content,
    required this.stance,
    required this.username,
    required this.displayName,
    required this.userId,
    this.avatarUrl,
    this.userIsPro = false,
    this.likeCount = 0,
    this.mediaUrls = const [],
    this.createdAt,
  });

  final String id;
  final String content;
  final String stance;
  final String username;
  final String displayName;
  final String userId;
  final String? avatarUrl;
  final bool userIsPro;
  final int likeCount;
  final List<String> mediaUrls;
  final DateTime? createdAt;

  factory EchoContextPreview.fromJson(Map<String, dynamic> json) {
    return EchoContextPreview(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      stance: json['stance'] as String? ?? 'support',
      username: json['username'] as String? ?? 'unknown',
      displayName:
          json['display_name'] as String? ??
          json['username'] as String? ??
          'unknown',
      userId: json['user_id'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      userIsPro: json['user_is_pro'] as bool? ?? false,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      mediaUrls: (json['media_urls'] as List?)?.cast<String>() ?? const [],
      createdAt: EchoEntity._dateFromJson(json['created_at']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    content,
    stance,
    username,
    displayName,
    userId,
    avatarUrl,
    userIsPro,
    likeCount,
    mediaUrls,
    createdAt,
  ];
}

class EchoReplyPreview extends Equatable {
  const EchoReplyPreview({
    required this.id,
    required this.content,
    required this.username,
    required this.displayName,
    required this.userId,
    this.avatarUrl,
    this.userTrustTier = 'unverified',
    this.userIsVerified = false,
    this.userIsPro = false,
    this.isLiked = false,
    this.isFromFollowed = false,
    this.likeCount = 0,
    this.childReplyCount = 0,
    this.createdAt,
  });

  final String id;
  final String content;
  final String username;
  final String displayName;
  final String userId;
  final String? avatarUrl;
  final String userTrustTier;
  final bool userIsVerified;
  final bool userIsPro;
  final bool isLiked;
  final bool isFromFollowed;
  final int likeCount;
  final int childReplyCount;
  final DateTime? createdAt;

  factory EchoReplyPreview.fromJson(Map<String, dynamic> json) {
    return EchoReplyPreview(
      id: json['id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      username: json['username'] as String? ?? 'unknown',
      displayName:
          json['display_name'] as String? ??
          json['username'] as String? ??
          'unknown',
      userId: json['user_id'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      userTrustTier: json['user_trust_tier'] as String? ?? 'unverified',
      userIsVerified: json['user_is_verified'] as bool? ?? false,
      userIsPro: json['user_is_pro'] as bool? ?? false,
      isLiked: json['is_liked'] as bool? ?? false,
      isFromFollowed: json['is_from_followed'] as bool? ?? false,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      childReplyCount: (json['child_reply_count'] as num?)?.toInt() ?? 0,
      createdAt: EchoEntity._dateFromJson(json['created_at']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    content,
    username,
    displayName,
    userId,
    avatarUrl,
    userTrustTier,
    userIsVerified,
    userIsPro,
    isLiked,
    isFromFollowed,
    likeCount,
    childReplyCount,
    createdAt,
  ];
}
