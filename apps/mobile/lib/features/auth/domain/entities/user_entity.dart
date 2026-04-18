// user domain entity — pure dart, no flutter or supabase dependencies

import 'package:equatable/equatable.dart';

class UserEntity extends Equatable {
  const UserEntity({
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

  @override
  List<Object?> get props => [
    id, username, trustTier, trustScore,
    isIdentityVerified, avatarUrl, walletAddress,
  ];
}