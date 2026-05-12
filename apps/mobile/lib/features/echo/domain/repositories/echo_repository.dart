// abstract echo repository — defines the contract
// implemented by EchoRepositoryImpl in the data layer

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/echo_entity.dart';

abstract class EchoRepository {
  Future<Either<Failure, List<EchoEntity>>> getFeed({
    required int offset,
    required int limit,
  });

  Future<Either<Failure, EchoEntity>> getEchoById(String id);

  Future<Either<Failure, EchoEntity>> createEcho({
    required String title,
    required String content,
    required EchoCategory category,
    required bool verificationRequired,
  });

  Future<Either<Failure, void>> interactWithEcho({
    required String echoId,
    required String type,
  });

  Future<Either<Failure, void>> reportEcho({
    required String echoId,
    required String reason,
    String? description,
  });
}