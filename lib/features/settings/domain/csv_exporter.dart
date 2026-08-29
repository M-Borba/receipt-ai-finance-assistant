import '../../../../core/format/money.dart';
import '../../expenses/domain/entities/expense_entity.dart';

/// Convierte los gastos en un CSV que Excel abre con doble clic.
///
/// Los detalles que hacen que funcione de verdad:
/// - **Separador `;`** en locales en espanol. Excel en espanol espera punto y
///   coma; con comas te mete todo en una sola columna.
/// - **Coma decimal** en esos mismos locales, para que Excel lo tome como
///   numero y no como texto.
/// - **BOM UTF-8** al principio, sin el cual Excel muestra "Caf" en vez de
///   "Café".
class CsvExporter {
  const CsvExporter();

  /// Excel necesita esto para entender que el archivo es UTF-8.
  static const bom = '﻿';

  static const _headers = [
    'Fecha',
    'Comercio',
    'Categoria',
    'Monto',
    'Nota',
    'Origen',
  ];

  /// `true` cuando el locale usa coma decimal y, por lo tanto, `;` de separador.
  static bool usesSemicolon(String locale) => !locale.toLowerCase().startsWith('en');

  String export(List<ExpenseEntity> expenses, {String? locale}) {
    final loc = locale ?? Money.locale;
    final sep = usesSemicolon(loc) ? ';' : ',';
    final decimalComma = usesSemicolon(loc);

    final buffer = StringBuffer(bom);
    buffer.writeln(_headers.map((h) => _escape(h, sep)).join(sep));

    // Mas viejo primero: es como se lee una planilla de gastos.
    final ordenados = [...expenses]..sort((a, b) => a.date.compareTo(b.date));

    for (final e in ordenados) {
      final fila = [
        _fecha(e.date),
        e.storeName ?? '',
        e.category.label,
        _monto(e.amountCents, decimalComma),
        e.note ?? '',
        e.isManual ? 'Manual' : 'Ticket',
      ];
      buffer.writeln(fila.map((c) => _escape(c, sep)).join(sep));
    }

    return buffer.toString();
  }

  /// ISO, que es lo unico que Excel interpreta igual en cualquier idioma.
  String _fecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _monto(int cents, bool decimalComma) {
    final digits = Money.decimalDigitsFor(Money.currencyCode);
    if (digits == 0) return cents.toString();

    final entero = cents ~/ 100;
    final resto = (cents % 100).abs().toString().padLeft(2, '0');
    return '$entero${decimalComma ? ',' : '.'}$resto';
  }

  /// Entrecomilla si el campo contiene el separador, comillas o saltos de
  /// linea. Las comillas internas se duplican, como manda el formato.
  String _escape(String value, String sep) {
    final needsQuotes =
        value.contains(sep) || value.contains('"') || value.contains('\n') || value.contains('\r');
    if (!needsQuotes) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Nombre sugerido: `gastos-2026-08-29.csv`
  String fileName(DateTime now) =>
      'gastos-${_fecha(now)}.csv';
}
