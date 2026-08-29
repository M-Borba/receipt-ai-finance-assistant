import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Descarga por navegador: se arma un blob y se dispara un click sobre un
/// enlace temporal.
Future<String?> saveFile({
  required String fileName,
  required String contents,
  required String mimeType,
}) async {
  final bytes = utf8.encode(contents);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);

  // El navegador lo pone donde el usuario tenga configurado: no hay ruta.
  return null;
}
