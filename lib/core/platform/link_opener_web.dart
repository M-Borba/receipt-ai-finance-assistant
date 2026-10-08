import 'package:web/web.dart' as web;

bool abrirLink(String url) {
  // En el celular, wa.me abre la app de WhatsApp directamente.
  web.window.open(url, '_blank');
  return true;
}
