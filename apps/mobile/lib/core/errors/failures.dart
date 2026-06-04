// failure types for the either<failure, t> pattern
// all repository errors are mapped to one of these before reaching the ui

abstract class Failure {
  const Failure(this.message);
  final String message;
}

class NetworkFailure extends Failure {
  const NetworkFailure(
      [super.message = 'network error — check your connection']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'authentication failed']);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'server error — try again']);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

class StorageFailure extends Failure {
  const StorageFailure([super.message = 'file upload failed']);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure([super.message = 'not found']);
}

class RateLimitFailure extends Failure {
  const RateLimitFailure([super.message = 'too many requests — slow down']);
}
