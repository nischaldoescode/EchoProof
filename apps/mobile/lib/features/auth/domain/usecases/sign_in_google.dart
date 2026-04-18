import 'package:dartz/dartz.dart';
import '../../../../core/errors/failures.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

class SignInGoogleUseCase {
  const SignInGoogleUseCase(this._repository);
  final AuthRepository _repository;

  Future<Either<Failure, UserEntity>> call() {
    return _repository.signInWithGoogle();
  }
}