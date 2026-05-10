// echo model — maps raw supabase rows to domain entities

import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../../../../core/utils/formatters.dart';

class EchoModel {
  static EchoEntity fromRow(Map<String, dynamic> row, Map<String, dynamic> user) {
    final created = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();

    return EchoEntity(
      id:             row['id'] as String,
      title:          row['title'] as String? ?? '',
      content:        row['content'] as String,
      username:       user['username'] as String,
      userTrustTier:  user['trust_tier'] as String? ?? 'unverified',
      userIsVerified: user['is_identity_verified'] as bool? ?? false,
      userAvatarUrl:  user['avatar_url'] as String?,
      category:       EchoCategory.fromString(row['category'] as String),
      status:         _parseStatus(row['status'] as String),
      confidenceScore:  (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
      trustScore:       (row['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
      supportCount:     (row['support_count'] as num?)?.toInt() ?? 0,
      challengeCount:   (row['challenge_count'] as num?)?.toInt() ?? 0,
      timeAgo:          Formatters.timeAgo(created),
      proofCount:       (row['proof_count'] as num?)?.toInt() ?? 0,
      userIsPro: user['is_pro'] as bool? ?? false,
    );
  }

  static EchoStatus _parseStatus(String v) => switch (v) {
    'pending_verification' => EchoStatus.pendingVerification,
    'active'               => EchoStatus.active,
    'under_review'         => EchoStatus.underReview,
    'verified'             => EchoStatus.verified,
    'controversial'        => EchoStatus.controversial,
    'disputed'             => EchoStatus.disputed,
    'hidden'               => EchoStatus.hidden,
    'rejected'             => EchoStatus.rejected,
    _                      => EchoStatus.pendingVerification,
  };
}