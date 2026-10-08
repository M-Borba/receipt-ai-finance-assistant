import 'link_opener_stub.dart'
    if (dart.library.js_interop) 'link_opener_web.dart' as impl;

/// Abre un link afuera de la app (WhatsApp, por ejemplo).
///
/// Sin `url_launcher` a proposito: la app corre en el navegador, y ahi alcanza
/// con abrir una pestana. Fuera de la web devuelve false y quien llama ofrece
/// copiar el texto.
bool abrirLink(String url) => impl.abrirLink(url);
