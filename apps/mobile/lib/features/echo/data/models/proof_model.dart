// proof model — maps echo_proofs rows

import '../../../../core/utils/formatters.dart';

class ProofModel {
  const ProofModel({
    required this.id,
    required this.echoId,
    required this.userId,
    required this.proofType,
    required this.proofUrl,
    required this.username,
    required this.timeAgo,
    this.description,
    this.stakeTx,
  });

  final String  id;
  final String  echoId;
  final String  userId;
  final String  proofType;
  final String  proofUrl;
  final String? description;
  final String  username;
  final String  timeAgo;
  final String? stakeTx;

  factory ProofModel.fromRow(Map<String, dynamic> row) {
    final created = DateTime.tryParse(row['created_at'] as String? ?? '') ?? DateTime.now();
    final user    = row['users_public'] as Map<String, dynamic>? ?? {};

    return ProofModel(
      id:          row['id'] as String,
      echoId:      row['echo_id'] as String,
      userId:      row['user_id'] as String,
      proofType:   row['proof_type'] as String? ?? 'url',
      proofUrl:    row['proof_url'] as String,
      description: row['description'] as String?,
      username:    user['username'] as String? ?? 'unknown',
      timeAgo:     Formatters.timeAgo(created),
      stakeTx:     row['stake_tx'] as String?,
    );
  }
}