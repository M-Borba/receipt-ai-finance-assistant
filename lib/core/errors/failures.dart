import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable {
  final String message;
  const Failure(this.message);

  @override
  List<Object> get props => [message];
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'Network error occurred']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Storage operation failed']);
}

class OcrFailure extends Failure {
  const OcrFailure([super.message = 'OCR processing failed']);
}

class AiFailure extends Failure {
  const AiFailure([super.message = 'AI processing failed']);
}

class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure({String message = 'Server error', this.statusCode})
      : super(message);

  @override
  List<Object> get props => [message, statusCode ?? 0];
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache operation failed']);
}

/// Entrada del usuario invalida. No es un fallo de infraestructura: el mensaje
/// se muestra tal cual en la UI.
class ValidationFailure extends Failure {
  const ValidationFailure([super.message = 'Datos invalidos']);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Unexpected error occurred']);
}
