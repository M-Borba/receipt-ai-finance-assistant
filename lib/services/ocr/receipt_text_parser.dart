import 'package:uuid/uuid.dart';

import '../../core/format/money.dart';

import '../../features/receipts/domain/entities/receipt_item_entity.dart';
import 'ocr_service.dart';

/// Turns raw OCR text into a structured [OcrResult].
///
/// Shared by every [OcrService] strategy (ML Kit, Tesseract, cloud OCR):
/// strategies only differ in HOW they extract text from the image, not in
/// how a receipt is interpreted.
///
/// Handles both anglosajon (`1,234.56`, `MM/DD/YYYY`) and LatAm/European
/// (`1.234,56`, `DD/MM/YYYY`) conventions, with keyword vocabularies in
/// Spanish and English.
class ReceiptTextParser {
  final _uuid = const Uuid();

  /// Tie-breaker for ambiguous dates like `03/07/2026`, where both numbers are
  /// valid months. Unambiguous dates (`25/12/2025`) resolve themselves
  /// regardless of this flag. Defaults to day-first (LatAm / Europe).
  final bool dayFirst;

  ReceiptTextParser({this.dayFirst = true});

  // ---------------------------------------------------------------------
  // Building blocks
  // ---------------------------------------------------------------------

  /// A monetary amount in either convention.
  /// Grouped form first (`1.234,56`, `1,234.56`), then plain (`43.20`, `1234`).
  static const _amount =
      r'\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?';

  /// Keywords meaning "this is what the customer pays".
  /// The lookbehind stops `total` from matching inside `SUBTOTAL`.
  static final _totalPattern = RegExp(
    r'(?<![a-záéíóúñ])'
    r'(?:total\s+a\s+pagar|importe\s+total|total\s+general|grand\s+total|'
    r'amount\s+due|total|importe|neto\s+a\s+pagar)'
    r'\s*:?\s*(?:[\$€£]|ars|mxn|clp|cop|pen|uyu|usd)?\s*'
    // Sin `r` a proposito: este tramo interpola _amount.
    '($_amount)',
    caseSensitive: false,
  );

  /// Lines that are receipt bookkeeping, not products.
  static final _nonItemPattern = RegExp(
    r'^\s*(?:sub\s*-?\s*total|total|importe|iva|i\.v\.a|impuesto|tax|'
    r'propina|tip|servicio|descuento|discount|ahorro|redondeo|ajuste|'
    r'efectivo|cash|cambio|vuelto|change|saldo|'
    r'tarjeta|card|credito|crédito|debito|débito|visa|mastercard|amex|'
    r'cuit|cuil|ruc|nit|rfc|tel|telefono|teléfono|'
    r'factura|ticket|comprobante|caja|cajero|atendio|atendió|'
    r'gracias|thank\s*you|www\.|@)',
    caseSensitive: false,
  );

  /// Fin del bloque de items: donde empieza el pie del ticket.
  static final _itemSectionEndPattern = RegExp(
    r'^\s*(?:impuestos?|adenda|tipo\s+neto|t\s+sub\s*-?\s*total|'
    r'sub\s*-?\s*total|total\b|resumen|forma\s+de\s+pago)',
    caseSensitive: false,
  );

  /// Ultima linea de encabezado antes del detalle. Se toma la mas cercana al
  /// final del encabezado: un ticket puede nombrar la moneda arriba y ademas
  /// tener una fila de titulos de columna justo antes de los productos.
  static final _itemSectionStartPattern = RegExp(
    r'^\s*(?:moneda\b|pesos\s+uruguayos|cant\b|cantidad\b|descripci|'
    r'detalle\b|articulo|precio\s+importe)',
    caseSensitive: false,
  );

  /// Monto pegado al final de la linea. Anclarlo importa: sin el ancla, el
  /// `1.` de "1. CARNE VACUNA" se leia como un precio de un peso.
  static final _trailingAmountPattern = RegExp('($_amount)' r'\s*$');

  /// Columnas numericas pegadas al principio de la linea: cantidad y codigo
  /// de articulo. `10 101  CATALANES REDONDOS` / `1. CARNE VACUNA`
  ///
  /// Solo se borran los numeros de los extremos. Los del medio son parte del
  /// nombre y hay que dejarlos: "Organic Milk 2%", "Cafe molido 500g",
  /// "Canciller Malbec 750 ml".
  static final _leadingColumnsPattern =
      RegExp(r'^(?:\d+(?:[.,]\d+)?[\s.]+)+');

  /// Una linea aporta nombre si tiene al menos una palabra de tres letras.
  /// `1.59  419.00  666.21` no aporta: es la fila de numeros del item de
  /// arriba.
  static final _namishPattern = RegExp(r'\p{L}{3,}', unicode: true);

  /// Item line with explicit quantity. `Empanadas 3 x $1.500,00`
  static final _itemQtyPattern = RegExp(
    r'^(.+?)\s+(\d+(?:[.,]\d+)?)\s*[x×*]\s*[\$€£]?\s*' '($_amount)',
    caseSensitive: false,
  );

  /// Keeps letters from any script, so `Café`, `Ñoquis` and `Açaí` survive.
  static final _itemNameJunk = RegExp(r"[^\p{L}\p{N}\s%&'./-]", unicode: true);

  static final _letterPattern = RegExp(r'\p{L}', unicode: true);

  /// Etiqueta de identificacion fiscal pegada al nombre del comercio. El OCR
  /// junta columnas: "MEDIALUNAS GUICHON S.R.L.  R.U.T." es una sola linea.
  static final _taxIdLabelPattern = RegExp(
    r'\s+(?:R\.?U\.?T\.?|C\.?U\.?I\.?T\.?|R\.?U\.?C\.?|N\.?I\.?T\.?)'
    r'\s*:?\s*\d*\s*$',
    caseSensitive: false,
  );

  static final _numericDatePattern =
      RegExp(r'(\d{1,4})[/\-.](\d{1,2})[/\-.](\d{2,4})');

  static final _currencyPattern = RegExp(
    r'(pesos\s+uruguayos|ARS|MXN|CLP|COP|PEN|UYU|BRL|EUR|USD|R\$|US\$|€|£)',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------

  OcrResult parse(String rawText, {double confidence = 0.0}) {
    // El total se calcula primero a proposito: acota los items. Ningun
    // producto puede costar mas que el ticket entero.
    final total = extractTotal(rawText);
    return OcrResult(
      rawText: rawText,
      items: parseItems(rawText, totalCents: total),
      storeName: extractStoreName(rawText),
      receiptDate: extractDate(rawText),
      totalCents: total,
      confidence: confidence,
    );
  }

  /// Normalises an amount written in either convention into a [double].
  /// Uso interno: para dinero usa [parseAmountCents].
  ///
  /// `1.234,56` -> 1234.56    `1,234.56` -> 1234.56
  /// `1.234`    -> 1234       `43,20`    -> 43.2
  ///
  /// Decides which separator is decimal by looking at the LAST one: three
  /// digits after it means grouping, one or two means decimals.
  static double? parseAmount(String raw) {
    final s = raw.replaceAll(RegExp(r'[^\d.,]'), '');
    if (s.isEmpty) return null;

    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    if (lastDot == -1 && lastComma == -1) return double.tryParse(s);

    final sep = lastDot > lastComma ? lastDot : lastComma;
    final decimals = s.length - sep - 1;
    final onlyOneKind = lastDot == -1 || lastComma == -1;

    // `1.234` / `1,234`: a price never has three decimals, so it is grouping.
    if (decimals == 3 && onlyOneKind) {
      return double.tryParse(s.replaceAll(RegExp(r'[.,]'), ''));
    }

    final intPart = s.substring(0, sep).replaceAll(RegExp(r'[.,]'), '');
    final decPart = s.substring(sep + 1);
    return double.tryParse('${intPart.isEmpty ? '0' : intPart}.$decPart');
  }

  /// The amount actually charged.
  ///
  /// Takes the LAST total-like match: on a real receipt the payable total sits
  /// at the bottom, below subtotal, taxes and discounts. `SUBTOTAL` can never
  /// match, thanks to the lookbehind.
  /// Un monto del ticket, en CENTAVOS.
  ///
  /// Toda la plata se maneja en enteros: ver [Money]. `parseAmount` sigue
  /// existiendo para cantidades (1,5 kg es un double legitimo).
  static int? parseAmountCents(String raw) {
    final major = parseAmount(raw);
    return major == null ? null : Money.fromMajor(major);
  }

  /// The amount actually charged, en centavos.
  ///
  /// Takes the LAST total-like match: on a real receipt the payable total sits
  /// at the bottom, below subtotal, taxes and discounts. `SUBTOTAL` can never
  /// match, thanks to the lookbehind.
  int? extractTotal(String text) {
    final matches = _totalPattern.allMatches(text).toList();
    for (final m in matches.reversed) {
      final cents = parseAmountCents(m.group(1)!);
      if (cents != null && cents > 0) return cents;
    }
    return null;
  }

  /// Currency hint found in the text. Null when the receipt only shows a bare
  /// `$`, which is ambiguous across ARS, MXN, CLP, COP, UYU and USD.
  String? extractCurrency(String text) {
    final m = _currencyPattern.firstMatch(text);
    if (m == null) return null;
    final raw = m.group(1)!.toUpperCase();
    return switch (raw) {
      '€' => 'EUR',
      '£' => 'GBP',
      'PESOS URUGUAYOS' => 'UYU',
      r'R$' => 'BRL',
      r'US$' => 'USD',
      _ => raw,
    };
  }

  /// El bloque donde viven los productos.
  ///
  /// Un e-Ticket de DGI tiene tres partes: encabezado (RUT, razon social,
  /// direccion), detalle, y pie (tabla de IVA, total, CAE, URLs de
  /// verificacion). Sin acotar, el numero de RUT y el de CAE entraban como
  /// productos de cientos de millones de pesos, y las filas de la tabla de
  /// IVA entraban como items con el monto del total.
  ///
  /// Verificado contra tickets uruguayos reales: ver `test/assets/ocr/`.
  List<String> sliceItemSection(List<String> lines) {
    var end = lines.length;
    for (var i = 0; i < lines.length; i++) {
      if (_itemSectionEndPattern.hasMatch(lines[i])) {
        end = i;
        break;
      }
    }

    var start = 0;
    for (var i = 0; i < end; i++) {
      if (_itemSectionStartPattern.hasMatch(lines[i])) start = i + 1;
    }

    // Si no aparece ningun marcador (ticket no fiscal, OCR pobre), se procesa
    // todo el texto: el filtro por total sigue descartando la basura.
    if (end - start < 1) return lines;
    return lines.sublist(start, end);
  }

  /// Productos del ticket.
  ///
  /// [totalCents] es opcional pero cambia mucho la precision: se usa para
  /// descartar cualquier linea cuyo "precio" supere el total del ticket.
  List<ReceiptItemEntity> parseItems(String text, {int? totalCents}) {
    final items = <ReceiptItemEntity>[];
    final lines = sliceItemSection(text.split('\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (isTotalLine(line)) continue;
      if (_numericDatePattern.hasMatch(line)) continue;

      final qtyMatch = _itemQtyPattern.firstMatch(line);
      if (qtyMatch != null) {
        final name = cleanItemName(qtyMatch.group(1)!);
        // La cantidad si es double: "1,5 kg" es valido. El precio no.
        final qty = parseAmount(qtyMatch.group(2)!) ?? 1.0;
        final unitCents = parseAmountCents(qtyMatch.group(3)!) ?? 0;
        if (unitCents > 0 && qty > 0 && name.length > 2) {
          items.add(ReceiptItemEntity(
            id: _uuid.v4(),
            name: name,
            quantity: qty,
            unitPriceCents: unitCents,
            // Redondeo al centavo: 3 x 33,33 son 99,99, no 100.
            totalPriceCents: (qty * unitCents).round(),
          ));
        }
        continue;
      }

      // Una linea sin palabras es la fila de numeros del producto anterior,
      // no un producto nuevo. Ya se leyo desde ahi, o no aporta nada.
      if (!_hasName(line)) continue;

      final name = cleanItemName(_stripColumns(line));
      if (name.length <= 2) continue;

      // El importe esta al final de la linea del nombre, o solo en la fila de
      // numeros que sigue. Cuando esta abajo la fila es
      // `cantidad  unitario  importe` y el importe es el ultimo.
      var cents = _trailingAmountCents(line);
      if (cents == null && i + 1 < lines.length && !_hasName(lines[i + 1])) {
        cents = _trailingAmountCents(lines[i + 1]);
      }
      if (cents == null || cents <= 0) continue;

      // Lo que descarta el RUT, el numero de CAE y las filas de la tabla de
      // IVA sin depender de como el OCR haya cortado las columnas.
      if (totalCents != null && cents > totalCents) continue;

      items.add(ReceiptItemEntity(
        id: _uuid.v4(),
        name: name,
        quantity: 1.0,
        unitPriceCents: cents,
        totalPriceCents: cents,
      ));
    }

    return items;
  }

  bool _hasName(String line) => _namishPattern.hasMatch(line);

  /// Deja solo el nombre: le saca las columnas numericas de adelante y el
  /// importe de atras.
  String _stripColumns(String line) {
    final sinPrecio = line.replaceFirst(_trailingAmountPattern, '');
    return sinPrecio.replaceFirst(_leadingColumnsPattern, '');
  }

  int? _trailingAmountCents(String line) {
    final m = _trailingAmountPattern.firstMatch(line);
    return m == null ? null : parseAmountCents(m.group(1)!);
  }

  bool isTotalLine(String line) => _nonItemPattern.hasMatch(line);

  /// Collapses whitespace and drops punctuation noise, keeping accents and ñ.
  String cleanItemName(String name) {
    return name
        .replaceAll(_itemNameJunk, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s./-]+|[\s./-]+$'), '')
        .trim();
  }

  String? extractStoreName(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines.take(4)) {
      if (line.length <= 3) continue;
      if (isTotalLine(line)) continue;
      if (_numericDatePattern.hasMatch(line)) continue;
      // Skip lines that are mostly digits: tax ids, phone numbers, addresses.
      final letters = _letterPattern.allMatches(line).length;
      if (letters * 2 < line.length) continue;
      return line.replaceAll(_taxIdLabelPattern, '').trim();
    }
    return null;
  }

  /// Parses the purchase date, resolving DD/MM vs MM/DD.
  ///
  /// Unambiguous dates decide themselves (`25/12/2025` can only be day-first);
  /// ambiguous ones fall back to [dayFirst]. Out-of-range combinations are
  /// rejected instead of silently overflowing into another year, which is what
  /// `DateTime(2026, 13, 7)` does.
  DateTime? extractDate(String text) {
    for (final match in _numericDatePattern.allMatches(text)) {
      final a = int.tryParse(match.group(1)!);
      final b = int.tryParse(match.group(2)!);
      final c = int.tryParse(match.group(3)!);
      if (a == null || b == null || c == null) continue;

      // ISO: YYYY-MM-DD
      if (match.group(1)!.length == 4) {
        final iso = _buildDate(a, b, c);
        if (iso != null) return iso;
        continue;
      }

      final year = c < 100 ? 2000 + c : c;

      final bool useDayFirst;
      if (a > 12 && b <= 12) {
        useDayFirst = true;
      } else if (b > 12 && a <= 12) {
        useDayFirst = false;
      } else {
        useDayFirst = dayFirst;
      }

      final parsed = _buildDate(
        year,
        useDayFirst ? b : a,
        useDayFirst ? a : b,
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  /// Builds a date only if the components are real (no month 13, no Feb 30)
  /// and the result is not in the future.
  static DateTime? _buildDate(int year, int month, int day) {
    if (year < 2000 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;

    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null; // Feb 30 & co.
    if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) return null;
    return date;
  }
}
