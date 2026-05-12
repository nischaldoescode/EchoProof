// auth repository implementation
// maps supabase auth calls to domain entities
// maps supabase exceptions to typed failures

import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/user_model.dart';
import '../sources/auth_remote_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._remoteSource);
  final AuthRemoteSource _remoteSource;

  @override
  Future<Either<Failure, UserEntity>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final model = await _remoteSource.signInWithEmail(
        email: email, password: password,
      );
      return Right(model.toEntity());
    } on AuthException catch (e) {
      AppLogger.error('auth repo: sign in failed', e);
      return Left(AuthFailure(e.message));
    } catch (e) {
      AppLogger.error('auth repo: unexpected error', e);
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, UserEntity>> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final model = await _remoteSource.signUpWithEmail(
        email: email, password: password,
      );
      return Right(model.toEntity());
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message));
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, UserEntity>> signInWithGoogle() async {
    try {
      final model = await _remoteSource.signInWithGoogle();
      return Right(model.toEntity());
    } on AuthException catch (e) {
      return Left(AuthFailure(e.message));
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, void>> signOut() async {
    try {
      await _remoteSource.signOut();
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, UserEntity?>> getCurrentUser() async {
    try {
      final model = await _remoteSource.getCurrentUser();
      return Right(model?.toEntity());
    } catch (e) {
      return Left(ServerFailure());
    }
  }
}