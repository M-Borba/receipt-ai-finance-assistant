import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:logger/logger.dart';

import '../../core/config/environment.dart';
import '../../core/errors/exceptions.dart';
import 'ocr_service.dart';
import 'receipt_text_parser.dart';

/// OCR strategy for Android/iOS backed by Google ML Kit (on-device).
class MlKitOcrService implements OcrService {
  final _parser = ReceiptTextParser(dayFirst: Environment.datesAreDayFirst);
  final _log = Logger();

  @override
  Future<OcrResult> processImage(String imagePath) async {
    final textRecognizer = TextRecognizer();
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await textRecognizer.processImage(inputImage);

      if (recognized.text.isEmpty) {
        throw const OcrException('No text detected in image');
      }

      final confidence = _estimateConfidence(recognized);
      if (confidence < Environment.ocrConfidenceThreshold) {
        _log.w('Low OCR confidence: $confidence');
      }

      return _parser.parse(recognized.text, confidence: confidence);
    } catch (e) {
      if (e is OcrException) rethrow;
      _log.e('ML Kit OCR error', error: e);
      throw OcrException('Failed to process image: $e');
    } finally {
      await textRecognizer.close();
    }
  }

  double _estimateConfidence(RecognizedText recognized) {
    if (recognized.blocks.isEmpty) return 0.0;
    double total = 0;
    int count = 0;
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          total += element.confidence ?? 0.0;
          count++;
        }
      }
    }
    return count > 0 ? total / count : 0.0;
  }
}
