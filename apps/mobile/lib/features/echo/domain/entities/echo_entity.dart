// echo entity — pure domain model, no flutter or supabase dependencies
// immutable value object using freezed pattern (manual here, add freezed later)
// this is what the ui layer works with — never raw db maps

import 'package:equatable/equatable.dart';
import 'echo_status.dart';

/// category of an echo — matches the sql echo_category enum exactly
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

  /// display name shown in ui chips and cards
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

/// trust tier — matches sql trust_tier enum
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
/// all fields are immutable — use copyWith to produce updated versions
class EchoEntity extends Equatable {
  const EchoEntity({
    required this.id,
    required this.title,
    required this.content,
    required this.username,
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
    this.proofCount = 0,
    this.requiresVerification = true,
    this.version = 1,
  });

  final String id;
  final String title;
  final String content;
  final String username;
  final String userTrustTier;
  final bool userIsVerified;
  final String? userAvatarUrl;
  final EchoCategory category;
  final EchoStatus status;

  /// 0.0 to 100.0 — percentage of weighted support
  final double confidenceScore;

  /// net weighted score = support_weight - challenge_weight
  final int trustScore;
  final int version;

  /// 0.0 to 100.0 — how balanced the split is
  final double controversyScore;

  final int supportCount;
  final int challengeCount;

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
      userTrustTier: json['user_trust_tier'] as String,
      userIsVerified: json['user_is_verified'] as bool,
      userAvatarUrl: json['user_avatar_url'] as String?,
      category: EchoCategory.fromString(json['category'] as String),
      status: EchoStatus.fromString(json['status'] as String),
      confidenceScore: (json['confidence_score'] as num).toDouble(),
      trustScore: json['trust_score'] as int,
      controversyScore: (json['controversy_score'] as num).toDouble(),
      supportCount: json['support_count'] as int,
      challengeCount: json['challenge_count'] as int,
      timeAgo: json['time_ago'] as String,
      proofCount: (json['proof_count'] as int?) ?? 0,
      requiresVerification: (json['requires_verification'] as bool?) ?? true,
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }

  EchoEntity copyWith({
    String? id,
    String? title,
    String? content,
    String? username,
    String? userTrustTier,
    bool? userIsVerified,
    String? userAvatarUrl,
    EchoCategory? category,
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

  }) {
    return EchoEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      username: username ?? this.username,
      userTrustTier: userTrustTier ?? this.userTrustTier,
      userIsVerified: userIsVerified ?? this.userIsVerified,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      category: category ?? this.category,
      status: status ?? this.status,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      trustScore: trustScore ?? this.trustScore,
      controversyScore: controversyScore ?? this.controversyScore,
      supportCount: supportCount ?? this.supportCount,
      challengeCount: challengeCount ?? this.challengeCount,
      timeAgo: timeAgo ?? this.timeAgo,
      proofCount: proofCount ?? this.proofCount,
      requiresVerification: requiresVerification ?? this.requiresVerification,
      version: version ?? this.version,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        content,
        username,
        userTrustTier,
        userIsVerified,
        userAvatarUrl,
        category,
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
      ];
}
