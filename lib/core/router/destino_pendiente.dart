/// A donde mandar al usuario, y como no perder el link con el que abrio la app.
///
/// Es logica pura, sin Flutter, para poder testearla: el bug que motivo este
/// archivo era una sola linea dentro de un closure de `redirect` y no habia
/// forma de escribirle un test.
library;

/// Rutas que nunca son un destino final. Volver a ellas despues de entrar
/// seria un rulo.
bool _esDePaso(String ruta) =>
    ruta.startsWith('/auth') || ruta.startsWith('/splash');

/// Valida una ruta que viene de la URL, o sea de afuera.
///
/// Tiene que empezar con una sola barra. `//evil.com` y `/\evil.com` los
/// interpretan los navegadores como URLs de otro dominio, asi que aceptarlas
/// convertiria cualquier link de la app en un redirect abierto: te mando
/// `.../join/x?from=//otro-dominio` y la app te lleva ahi con toda naturalidad.
String? _rutaUsable(String? ruta) {
  if (ruta == null || ruta.isEmpty) return null;
  if (!ruta.startsWith('/')) return null;
  if (ruta.startsWith('//') || ruta.startsWith(r'/\')) return null;
  if (_esDePaso(ruta)) return null;
  return ruta;
}

/// El destino que quedo guardado en el query `from`.
String? destinoGuardado(Uri uri) =>
    _rutaUsable(uri.queryParameters['from']);

String _con(String ruta, String? destino) =>
    destino == null ? ruta : '$ruta?from=${Uri.encodeComponent(destino)}';

/// Decide la redireccion. `null` significa "quedate donde estas".
///
/// El deep link viaja en el query `from` mientras se pasa por el splash y por
/// el login. **Sin eso el link de invitacion solo funcionaba para quien ya
/// tenia la sesion abierta**: a quien no, y es el caso normal porque lo estan
/// invitando justamente porque todavia no esta, se lo mandaba a `/auth/login`
/// pelado, y despues de crearse la cuenta caia en el dashboard sin grupo y sin
/// ningun mensaje. La invitacion se perdia en silencio.
String? decidirRedireccion({
  required Uri uri,
  required String rutaActual,
  required bool cargandoSesion,
  required bool logueado,
}) {
  final enSplash = rutaActual == '/splash';
  final enAuth = rutaActual.startsWith('/auth');

  // El destino esta en la URL misma cuando recien llego por el link, y en
  // `from` cuando ya paso por el splash o por el login.
  final destino = destinoGuardado(uri) ??
      (enSplash || enAuth ? null : _rutaUsable(uri.toString()));

  // Mientras Firebase resuelve la sesion, `logueado` todavia no significa
  // nada. Tratarlo como "no logueado" mandaba al login por un instante y se
  // comia el deep link.
  if (cargandoSesion) return enSplash ? null : _con('/splash', destino);

  if (!logueado) return enAuth ? null : _con('/auth/login', destino);

  if (enAuth || enSplash) return destino ?? '/dashboard';
  return null;
}

/// Le pega el `from` actual a una ruta, para pasar de login a registro sin
/// perder el link. Sin esto, tocar "Crear cuenta" perdia la invitacion.
String rutaConservandoDestino(String ruta, Uri uriActual) =>
    _con(ruta, destinoGuardado(uriActual));
