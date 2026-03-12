/// Base exception type for all WeldTrace application errors.
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message${cause != null ? ' ($cause)' : ''}';
}

/// Network or HTTP-level failures.
class NetworkException extends AppException {
  const NetworkException(super.message, [super.cause]);
}

/// API returned a non-2xx response.
class ApiException extends AppException {
  const ApiException(super.message, {this.statusCode, super.cause});

  final int? statusCode;
}

/// Authentication failures (invalid credentials, expired token, etc.).
class AuthException extends AppException {
  const AuthException(super.message, [super.cause]);
}

/// Local database failures.
class DatabaseException extends AppException {
  const DatabaseException(super.message, [super.cause]);
}

/// BLE / Sensor connection failures.
class SensorException extends AppException {
  const SensorException(super.message, [super.cause]);
}

/// Data sync failures.
class SyncException extends AppException {
  const SyncException(super.message, [super.cause]);
}

/// Weld business-rule violations (e.g. machine not approved, parameter out of range).
class WeldValidationException extends AppException {
  const WeldValidationException(super.message);
}
