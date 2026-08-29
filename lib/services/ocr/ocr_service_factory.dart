import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/config/environment.dart';
import 'ml_kit_ocr_service.dart';
import 'ocr_service.dart';
import 'ollama_ocr_service.dart';
import 'tesseract/tesseract_ocr_service.dart';

part 'ocr_service_factory.g.dart';

/// Factory that selects the [OcrService] strategy for the current platform.
///
/// This is the ONLY place that decides which OCR engine runs. To move to a
/// cloud OCR (e.g. Google Cloud Vision), implement [OcrService] once and
/// return it here — no other code changes.
@riverpod
OcrService ocrService(Ref ref) {
  if (Environment.ocrProvider == 'ollama') {
    return OllamaOcrService(
      baseUrl: Environment.ollamaBaseUrl,
      model: Environment.ollamaOcrModel,
    );
  }
  if (kIsWeb) return TesseractOcrService();
  return MlKitOcrService();
}
