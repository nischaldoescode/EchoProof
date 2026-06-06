// echo repository implementation
// translates between data sources and domain entities
// maps exceptions to failures

import 'package:dartz/dartz.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/errors/exceptions.dart' hide StorageException;
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/logger.dart';
import '../../domain/entities/echo_entity.dart';
import '../../domain/repositories/echo_repository.dart';
import '../sources/echo_remote_source.dart';

class EchoRepositoryImpl implements EchoRepository {
  const EchoRepositoryImpl(this._remoteSource);
  final EchoRemoteSource _remoteSource;

  @override
  Future<Either<Failure, List<EchoEntity>>> getFeed({
    required int offset,
    required int limit,
  }) async {
    try {
      final echoes =
          await _remoteSource.fetchFeed(offset: offset, limit: limit);
      return Right(echoes);
    } on NetworkException catch (e) {
      AppLogger.error('repo: get feed failed', e);
      return Left(NetworkFailure(e.message));
    } catch (e) {
      AppLogger.error('repo: get feed unexpected', e);
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, EchoEntity>> getEchoById(String id) async {
    try {
      final echo = await _remoteSource.fetchById(id);
      return Right(echo);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') return Left(NotFoundFailure());
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, EchoEntity>> createEcho({
    required String title,
    required String content,
    required EchoCategory category,
    required bool verificationRequired,
  }) async {
    try {
      final echo = await _remoteSource.createEcho(
        title: title,
        content: content,
        category: category,
        verificationRequired: verificationRequired,
      );
      return Right(echo);
    } on PostgrestException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, void>> interactWithEcho({
    required String echoId,
    required String type,
  }) async {
    try {
      await _remoteSource.interact(echoId: echoId, type: type);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, void>> reportEcho({
    required String echoId,
    required String reason,
    String? description,
  }) async {
    try {
      await _remoteSource.report(
          echoId: echoId, reason: reason, description: description);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure());
    }
  }
}
