class NetworkException implements Exception {
  final String message;
  const NetworkException([this.message = 'Network error occurred']);
}

class AuthException implements Exception {
  final String message;
  const AuthException([this.message = 'Authentication failed']);
}

class StorageException implements Exception {
  final String message;
  const StorageException([this.message = 'Storage operation failed']);
}

class OcrException implements Exception {
  final String message;
  const OcrException([this.message = 'OCR processing failed']);
}

class AiException implements Exception {
  final String message;
  const AiException([this.message = 'AI processing failed']);
}

class ServerException implements Exception {
  final String message;
  final int? statusCode;
  const ServerException({this.message = 'Server error', this.statusCode});
}
