import 'failures.dart';

/// Cuanto se espera una escritura a Firestore antes de darla por perdida.
///
/// Sin esto, `batch.commit()` y `add()` no resuelven NUNCA cuando no hay red:
/// se quedan esperando la confirmacion del servidor. La pantalla quedaba con el
/// spinner puesto para siempre, sin exito ni error y sin boton de salida.
///
/// 20 segundos es holgado para una conexion mala y corto para no parecer
/// colgado.
const escrituraTimeout = Duration(seconds: 20);

/// El fallo que corresponde cuando se agota [escrituraTimeout].
///
/// El mensaje NO dice "no se guardo", porque no se sabe: Firestore encola la
/// escritura y la manda cuando vuelve la red. Decir que fallo cuando en dos
/// minutos va a aparecer es peor que decir la verdad.
NetworkFailure timeoutAlGuardar(String queCosa) => NetworkFailure(
      'Se está tardando demasiado en guardar $queCosa. Revisá la conexión: '
      'si volvés a tener señal puede guardarse solo.',
    );
