import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart' as impl;

/// Entrega un archivo generado al usuario.
///
/// En web dispara la descarga del navegador; en nativo lo escribe en el
/// directorio de documentos y devuelve la ruta.
class FileSaver {
  const FileSaver();

  /// Devuelve la ruta donde quedo el archivo, o null si el navegador lo
  /// descargo y no hay ruta que mostrar.
  Future<String?> save({
    required String fileName,
    required String contents,
    String mimeType = 'text/csv',
  }) =>
      impl.saveFile(fileName: fileName, contents: contents, mimeType: mimeType);
}
