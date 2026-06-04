// report echo
// @params none

import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../repositories/echo_repository.dart';

class ReportEchoUseCase {
  const ReportEchoUseCase(this._repository);
  final EchoRepository _repository;

  Future<Either<Failure, void>> call({
    required String echoId,
    required String reason,
    String? description,
  }) {
    return _repository.reportEcho(
      echoId: echoId,
      reason: reason,
      description: description,
    );
  }
}
