import '../../../core/format/money.dart';
import 'insights_locales.dart';

/// Un evento de calendario que se repite todos los meses, con alarma, para
/// que el recordatorio de un gasto fijo lo de el celular y no la app.
///
/// Es la forma de tener recordatorios sin servidor: las notificaciones push
/// necesitan uno que mire los datos, y en iPhone solo andan con la PWA
/// instalada. Un `.ics` lo abre el calendario de cualquier telefono.
///
/// Evento de dia entero, con la alarma a las 9 de la manana de ese dia.
String icsRecordatorio(GastoFijo fijo, {required DateTime hoy}) {
  // Un dia 29, 30 o 31 no existe en todos los meses, y con BYMONTHDAY esos
  // meses el calendario saltea el evento. El 28 existe siempre.
  final dia = fijo.diaTipico > 28 ? 28 : fijo.diaTipico;
  final primero = hoy.day <= dia
      ? DateTime(hoy.year, hoy.month, dia)
      : DateTime(hoy.year, hoy.month + 1, dia);
  final titulo = _escapar('Pagar ${fijo.nombre}');
  final detalle = _escapar(
      'Suele ser unos ${Money.format(fijo.montoTipico)}. Recordatorio de '
      'ReceiptAI.');

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//ReceiptAI//Gastos fijos//ES',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    // Fijo por comercio: importarlo dos veces actualiza el evento en vez de
    // duplicarlo, en los calendarios que respetan el UID.
    'UID:fijo-${fijo.clave.replaceAll(' ', '-')}@mborba-proyect.web.app',
    'DTSTAMP:${_utc(hoy)}',
    'DTSTART;VALUE=DATE:${_fecha(primero)}',
    'RRULE:FREQ=MONTHLY;BYMONTHDAY=$dia',
    'SUMMARY:$titulo',
    'DESCRIPTION:$detalle',
    'BEGIN:VALARM',
    'ACTION:DISPLAY',
    'TRIGGER;RELATED=START:PT9H',
    'DESCRIPTION:$titulo',
    'END:VALARM',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].map(_plegar).join('\r\n'); // El formato exige CRLF.
}

String _dos(int n) => n.toString().padLeft(2, '0');

String _fecha(DateTime d) => '${d.year}${_dos(d.month)}${_dos(d.day)}';

String _utc(DateTime d) {
  final u = d.toUtc();
  return '${_fecha(u)}T${_dos(u.hour)}${_dos(u.minute)}${_dos(u.second)}Z';
}

/// RFC 5545: barra, coma, punto y coma y saltos de linea van escapados.
String _escapar(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(',', r'\,')
    .replaceAll(';', r'\;')
    .replaceAll('\n', r'\n');

/// RFC 5545: ninguna linea pasa de 75 bytes; las largas siguen en la de abajo
/// empezando con un espacio. Se corta a los 60 caracteres porque una tilde
/// ocupa dos bytes y el nombre de un comercio puede tenerlas.
String _plegar(String linea) {
  if (linea.length <= 60) return linea;
  final partes = <String>[];
  for (var i = 0; i < linea.length; i += 60) {
    final fin = i + 60 < linea.length ? i + 60 : linea.length;
    partes.add(linea.substring(i, fin));
  }
  return partes.join('\r\n ');
}
