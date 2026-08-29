import '../ocr_service.dart';

/// Non-web stub. The OCR factory only selects Tesseract on web.
class TesseractOcrService implements OcrService {
  @override
  Future<OcrResult> processImage(String imagePath) {
    throw UnsupportedError('TesseractOcrService is only available on the web');
  }
}
