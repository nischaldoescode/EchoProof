import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/echo_entity.dart';
import '../repositories/echo_repository.dart';

class FetchFeedUseCase {
  const FetchFeedUseCase(this._repository);
  final EchoRepository _repository;

  Future<Either<Failure, List<EchoEntity>>> call({int offset = 0, int limit = 20}) {
    return _repository.getFeed(offset: offset, limit: limit);
  }
}