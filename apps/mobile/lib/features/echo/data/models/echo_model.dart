// echo model — maps raw supabase rows to domain entities

import '../../domain/entities/echo_entity.dart';
import '../../domain/entities/echo_status.dart';
import '../../../../core/utils/formatters.dart';

class EchoModel {
  static EchoEntity fromRow(
      Map<String, dynamic> row, Map<String, dynamic> user) {
    final created =
        DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();

    return EchoEntity(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      content: row['content'] as String,
      username: user['username'] as String,
      userDisplayName:
          (user['display_name'] as String?)?.trim().isNotEmpty == true
              ? user['display_name'] as String
              : user['username'] as String,
      userTrustTier: user['trust_tier'] as String? ?? 'unverified',
      userIsVerified: user['is_identity_verified'] as bool? ?? false,
      userAvatarUrl: user['avatar_url'] as String?,
      category: EchoCategory.fromString(row['category'] as String),
      categoryDetail: row['category_detail'] as String?,
      status: _parseStatus(row['status'] as String),
      confidenceScore: (row['confidence_score'] as num?)?.toDouble() ?? 0.0,
      trustScore: (row['trust_score'] as num?)?.toInt() ?? 0,
      controversyScore: (row['controversy_score'] as num?)?.toDouble() ?? 0.0,
      supportCount: (row['context_support_count'] as num?)?.toInt() ??
          (row['support_count'] as num?)?.toInt() ??
          0,
      challengeCount: (row['context_challenge_count'] as num?)?.toInt() ??
          (row['challenge_count'] as num?)?.toInt() ??
          0,
      contextSupportCount: (row['context_support_count'] as num?)?.toInt() ?? 0,
      contextChallengeCount:
          (row['context_challenge_count'] as num?)?.toInt() ?? 0,
      publicVerdict: row['public_verdict'] as String? ?? 'open',
      publicVerdictAt: _parseDate(row['public_verdict_at']),
      publicContextClosesAt: _parseDate(row['public_context_closes_at']),
      publicContextMinCount:
          (row['public_context_min_count'] as num?)?.toInt() ?? 7,
      publicContextDecisionReason:
          row['public_context_decision_reason'] as String?,
      contextScore: (row['context_score'] as num?)?.toInt() ?? 0,
      timeAgo: Formatters.timeAgo(created),
      proofCount: (row['proof_count'] as num?)?.toInt() ?? 0,
      userIsPro: user['is_pro'] as bool? ?? false,
      mediaUrls: (row['media_urls'] as List?)?.cast<String>() ?? const [],
      replyCount: (row['reply_count'] as num?)?.toInt() ?? 0,
      userId: row['user_id'] as String? ?? '',
      createdRecordTx: row['created_record_tx'] as String?,
      createdRecordAt: _parseDate(row['created_record_at']),
      solanaStatus: row['solana_status'] as String? ?? 'pending',
      solanaError: row['solana_error'] as String?,
      verifiedRecordTx: row['verified_record_tx'] as String?,
      verifiedRecordAt: _parseDate(row['verified_record_at']),
      verifiedRecordStatus:
          row['verified_record_status'] as String? ?? 'pending',
      verifiedRecordError: row['verified_record_error'] as String?,
      bondCount: (row['bond_count'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static EchoStatus _parseStatus(String v) => switch (v) {
        'pending_verification' => EchoStatus.pendingVerification,
        'active' => EchoStatus.active,
        'under_review' => EchoStatus.underReview,
        'verified' => EchoStatus.verified,
        'controversial' => EchoStatus.controversial,
        'disputed' => EchoStatus.disputed,
        'hidden' => EchoStatus.hidden,
        'rejected' => EchoStatus.rejected,
        _ => EchoStatus.pendingVerification,
      };
}
