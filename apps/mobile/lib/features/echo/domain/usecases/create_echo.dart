// create echo use case

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/echo_entity.dart';
import '../repositories/echo_repository.dart';

class CreateEchoUseCase {
  const CreateEchoUseCase(this._repository);
  final EchoRepository _repository;

  Future<Either<Failure, EchoEntity>> call({
    required String title,
    required String content,
    required EchoCategory category,
    required bool verificationRequired,
  }) {
    return _repository.createEcho(
      title: title,
      content: content,
      category: category,
      verificationRequired: verificationRequired,
    );
  }
}
