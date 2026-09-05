import 'dart:async';
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

  /// Cuanto se espera al OCR.
  ///
  /// Eran 20 segundos, y dentro de esa ventana entraba TAMBIEN la descarga del
  /// motor wasm y de los `.traineddata` desde un CDN. En un celular con datos
  /// moviles no llegaba nunca: el escaneo, que es la puerta de entrada de la
  /// app, fallaba siempre en el telefono.
  ///
  /// El timeout no es una optimizacion, es una red para que la pantalla no
  /// quede colgada. Vale mas que sea generoso.
  static const _timeout = Duration(minutes: 2);

  /// Solo español. Antes cargaba `eng+spa`, o sea el doble de datos a bajar,
  /// para leer tickets uruguayos que estan en español.
  static const _idioma = 'spa';

  @override
  Future<OcrResult> processImage(String imagePath) async {
    if (_tesseractGlobal == null) {
      throw const OcrException(
        'Tesseract.js is not loaded. Check the script tag in web/index.html',
      );
    }

    try {
      final result = await _recognize(imagePath.toJS, _idioma.toJS)
          .toDart
          .timeout(_timeout);

      final text = result.data.text;

      if (text.trim().isEmpty) {
        throw const OcrException('No text detected in image');
      }

      // Tesseract reports confidence as 0-100; normalize to 0-1 like ML Kit.
      final confidence = result.data.confidence / 100.0;
      return _parser.parse(text, confidence: confidence);
    } on TimeoutException catch (_) {
      // Un TimeoutException crudo en pantalla no le dice nada a nadie.
      throw const OcrException(
        'La lectura tardo demasiado. Con buena señal suele andar; si no, '
        'cargá el gasto a mano.',
      );
    } catch (e) {
      if (e is OcrException) rethrow;
      _log.e('Tesseract OCR error', error: e);
      throw OcrException('No se pudo leer el ticket: $e');
    }
  }
}
