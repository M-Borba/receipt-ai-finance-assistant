import '../../../core/format/money.dart';

/// El texto para pedirle a alguien que salde lo que debe.
///
/// Sin cobrar ni acusar: es un mensaje que se manda a un amigo, y el numero lo
/// dice la app, no vos.
String mensajeRecordatorio({
  required String grupo,
  required int cents,
  required String moneda,
  required String link,
}) =>
    'Hola! En "$grupo" la app dice que me debés '
    '${Money.format(cents, code: moneda)}. Lo podés ver acá: $link';

/// Link de WhatsApp con el texto ya escrito. Sin numero: WhatsApp pregunta a
/// quien mandarlo, porque la app no guarda telefonos.
String linkWhatsApp(String texto) =>
    'https://wa.me/?text=${Uri.encodeComponent(texto)}';
