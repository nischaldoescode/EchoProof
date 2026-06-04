// interact echo
// @params none

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/echo_repository.dart';

class InteractEchoUseCase {
  const InteractEchoUseCase(this._repository);
  final EchoRepository _repository;

  Future<Either<Failure, void>> call({
    required String echoId,
    required String type,
  }) {
    return _repository.interactWithEcho(echoId: echoId, type: type);
  }
}
