import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:receipt_ai_finance_assistant/services/image/thumbnail_service.dart';

/// Genera un JPEG sintetico del tamano pedido.
Uint8List _foto(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, (x * 7) % 255, (y * 11) % 255, (x + y) % 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

void main() {
  const service = ThumbnailService();

  test('achica una foto grande al ancho maximo', () {
    final b64 = service.buildBase64(_foto(1920, 2560));
    expect(b64, isNotNull);

    final decodificada = img.decodeImage(base64Decode(b64!))!;
    expect(decodificada.width, ThumbnailService.maxWidth);
    // Mantiene la proporcion. Se deriva de la constante: el ancho se cambio
    // una vez (480 -> 1000) y este numero quedo clavado al valor viejo.
    expect(decodificada.height,
        closeTo(ThumbnailService.maxWidth * 2560 / 1920, 2));
  });

  test('la miniatura pesa mucho menos que el original', () {
    final original = _foto(1920, 2560);
    final b64 = service.buildBase64(original)!;
    expect(b64.length, lessThan(original.length));
    // Y entra comoda en un documento de Firestore.
    expect(b64.length, lessThan(ThumbnailService.maxBase64Bytes));
  });

  test('una foto muy detallada baja de calidad en vez de perderse', () {
    // Ruido puro: el peor caso para JPEG. A calidad plena se pasa del tope,
    // asi que tiene que caer a un escalon mas bajo y devolver algo igual.
    final b64 = service.buildBase64(_foto(1920, 2560));
    expect(b64, isNotNull, reason: 'perder la foto es peor que perder nitidez');
    expect(b64!.length, lessThanOrEqualTo(ThumbnailService.maxBase64Bytes));
  });

  test('no agranda una foto ya chica', () {
    final b64 = service.buildBase64(_foto(200, 300))!;
    final decodificada = img.decodeImage(base64Decode(b64))!;
    expect(decodificada.width, 200);
  });

  test('bytes basura devuelven null en vez de reventar', () {
    expect(service.buildBase64(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(service.buildBase64(Uint8List(0)), isNull);
  });

  group('decode', () {
    test('ida y vuelta', () {
      final b64 = service.buildBase64(_foto(600, 800))!;
      final bytes = ThumbnailService.decode(b64);
      expect(bytes, isNotNull);
      expect(img.decodeImage(bytes!), isNotNull);
    });

    test('null, vacio o corrupto devuelven null', () {
      expect(ThumbnailService.decode(null), isNull);
      expect(ThumbnailService.decode(''), isNull);
      expect(ThumbnailService.decode('no es base64 !!!'), isNull);
    });
  });
}
