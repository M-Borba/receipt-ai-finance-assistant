/// OCR strategy for the web backed by Tesseract.js (runs in the browser).
///
/// The real implementation lives in `tesseract_ocr_service_web.dart` and uses
/// `dart:js_interop`, which only compiles on web. On other platforms the stub
/// is compiled instead and throws if ever instantiated (the factory in
/// `ocr_service_factory.dart` never selects it outside the web).
export 'tesseract_ocr_service_stub.dart'
    if (dart.library.js_interop) 'tesseract_ocr_service_web.dart';
