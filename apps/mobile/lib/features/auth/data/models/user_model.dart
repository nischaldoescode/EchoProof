// user model — raw db row to domain entity mapping

import '../../domain/entities/user_entity.dart';

class UserModel {
  const UserModel({
    required this.id,
    required this.username,
    required this.trustTier,
    required this.trustScore,
    required this.isIdentityVerified,
    this.avatarUrl,
    this.walletAddress,
  });

  final String  id;
  final String  username;
  final String  trustTier;
  final int     trustScore;
  final bool    isIdentityVerified;
  final String? avatarUrl;
  final String? walletAddress;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:                 json['id'] as String,
      username:           json['username'] as String,
      trustTier:          json['trust_tier'] as String? ?? 'unverified',
      trustScore:         (json['trust_score'] as num?)?.toInt() ?? 0,
      isIdentityVerified: json['is_identity_verified'] as bool? ?? false,
      avatarUrl:          json['avatar_url'] as String?,
      walletAddress:      json['wallet_address'] as String?,
    );
  }

  UserEntity toEntity() {
    return UserEntity(
      id:                 id,
      username:           username,
      trustTier:          trustTier,
      trustScore:         trustScore,
      isIdentityVerified: isIdentityVerified,
      avatarUrl:          avatarUrl,
      walletAddress:      walletAddress,
    );
  }
}