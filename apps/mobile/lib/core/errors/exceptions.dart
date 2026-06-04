// typed exceptions thrown by data sources
// mapped to failure types by repository implementations

class NetworkException implements Exception {
  const NetworkException([this.message = 'network error']);
  final String message;
  @override
  String toString() => message;
}

class AuthException implements Exception {
  const AuthException([this.message = 'auth error']);
  final String message;
  @override
  String toString() => message;
}

class ServerException implements Exception {
  const ServerException([this.message = 'server error']);
  final String message;
  @override
  String toString() => message;
}

class StorageException implements Exception {
  const StorageException([this.message = 'storage error']);
  final String message;
  @override
  String toString() => message;
}
