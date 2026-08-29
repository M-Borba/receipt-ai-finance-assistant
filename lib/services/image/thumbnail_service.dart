import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Guarda la foto del ticket EN FIRESTORE, reducida.
///
/// Firebase Storage exige plan Blaze en proyectos nuevos, asi que Firestore
/// es el storage. No es un parche: el plan gratuito da 1 GiB, o sea unos 8.000
/// tickets a este tamaño. Escaneando tres por dia son siete años.
///
/// Y para grupos es mejor que un blob store aparte: que un amigo vea la foto
/// del ticket compartido es **la misma regla de membresia** que el ticket ya
/// necesita. Con Supabase o R2 habria que duplicar el modelo de permisos en un
/// segundo sistema.
///
/// Corre con `package:image`, Dart puro, asi que funciona igual en web y en
/// nativo. `flutter_image_compress` no soporta web.
class ThumbnailService {
  const ThumbnailService();

  /// Ancho maximo. A 1000px se leen los items y los importes de un e-Ticket
  /// uruguayo, no solo se reconoce cual es. Medido sobre las fotos de
  /// `test/assets/`: entre 84 y 160 KB en base64.
  ///
  /// A 480px pesaba 30 KB pero el detalle del ticket era ilegible, que es
  /// justo para lo que se guarda la foto: como respaldo de lo que se compro.
  static const maxWidth = 1000;

  /// Calidad JPEG. 70 en vez de 55: la diferencia son ~40 KB por ticket y se
  /// nota en el texto chico, que es lo unico que importa aca.
  static const quality = 70;

  /// Tope duro. Un documento de Firestore no puede pasar 1 MiB contando TODOS
  /// sus campos. El maximo medido es 160 KB, asi que hay margen de sobra; el
  /// tope existe para una foto rara, no para el caso normal.
  static const maxBase64Bytes = 600 * 1024;

  /// Devuelve la miniatura en base64, o null si no se pudo generar o quedo
  /// Escalones de respaldo, del mejor al peor. Si una foto muy detallada se
  /// pasa del tope, se baja la calidad antes de resignarla: perder resolucion
  /// es mucho mejor que quedarse sin foto.
  static const _escalones = <(int, int)>[
    (maxWidth, quality),
    (maxWidth, 45),
    (640, 45),
  ];

  /// demasiado grande. Que falle nunca debe impedir guardar el ticket.
  String? buildBase64(Uint8List original) {
    try {
      final decoded = img.decodeImage(original);
      if (decoded == null) return null;

      for (final (ancho, calidad) in _escalones) {
        // Solo achicar: agrandar una foto chica no aporta nada y pesa mas.
        final resized = decoded.width > ancho
            ? img.copyResize(decoded,
                width: ancho, interpolation: img.Interpolation.average)
            : decoded;

        final b64 = base64Encode(img.encodeJpg(resized, quality: calidad));
        if (b64.length <= maxBase64Bytes) return b64;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Para mostrarla: base64 a bytes. Null si el dato esta corrupto.
  static Uint8List? decode(String? base64Data) {
    if (base64Data == null || base64Data.isEmpty) return null;
    try {
      return base64Decode(base64Data);
    } catch (_) {
      return null;
    }
  }
}
