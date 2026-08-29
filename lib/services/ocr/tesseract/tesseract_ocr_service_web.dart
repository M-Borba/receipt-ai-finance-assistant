import 'dart:js_interop';

import 'package:logger/logger.dart';

import '../../../core/errors/exceptions.dart';
import '../ocr_service.dart';
import '../receipt_text_parser.dart';

@JS('Tesseract.recognize')
external JSPromise<_TesseractResult> _recognize(
  JSString image,
  JSString langs,
);

@JS('Tesseract')
external JSAny? get _tesseractGlobal;

extension type _TesseractResult._(JSObject _) implements JSObject {
  external _TesseractData get data;
}

extension type _TesseractData._(JSObject _) implements JSObject {
  external String get text;
  external double get confidence;
}

/// OCR strategy for the web backed by Tesseract.js.
///
/// Requires the Tesseract.js script tag in `web/index.html`. Receives the
/// blob URL that `image_picker` produces on web as [processImage]'s path.
class TesseractOcrService implements OcrService {
  final _parser = ReceiptTextParser();
  final _log = Logger();

  @override
  Future<OcrResult> processImage(String imagePath) async {
    if (_tesseractGlobal == null) {
      throw const OcrException(
        'Tesseract.js is not loaded. Check the script tag in web/index.html',
      );
    }

    try {
      final result = await _recognize(imagePath.toJS, 'eng+spa'.toJS)
          .toDart
          .timeout(const Duration(seconds: 20));
      
      final text = result.data.text;

      if (text.trim().isEmpty) {
        throw const OcrException('No text detected in image');
      }

      // Tesseract reports confidence as 0-100; normalize to 0-1 like ML Kit.
      final confidence = result.data.confidence / 100.0;
      return _parser.parse(text, confidence: confidence);
    } catch (e) {
      if (e is OcrException) rethrow;
      _log.e('Tesseract OCR error', error: e);
      throw OcrException('Failed to process image: $e');
    }
  }
}
