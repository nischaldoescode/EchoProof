// interaction model maps echo_interactions rows

class InteractionModel {
  const InteractionModel({
    required this.id,
    required this.echoId,
    required this.userId,
    required this.type,
    required this.weight,
    required this.createdAt,
  });

  final String id;
  final String echoId;
  final String userId;
  final String type;
  final int weight;
  final DateTime createdAt;

  factory InteractionModel.fromRow(Map<String, dynamic> row) {
    return InteractionModel(
      id: row['id'] as String,
      echoId: row['echo_id'] as String,
      userId: row['user_id'] as String,
      type: row['type'] as String,
      weight: (row['weight'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
