import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/services/ocr/receipt_text_parser.dart';

/// Tickets reales abreviados. El parser es la pieza mas fragil del pipeline:
/// si lee mal el monto, todo lo que hay aguas abajo (expense, dashboard,
/// insights de la IA) queda mal en silencio.
const _ticketArgentina = '''
COTO CICSA
Av. Rivadavia 5000 - CABA
CUIT 30-54808315-6
Ticket 0012-00043215
Fecha 25/12/2025 20:14

Café molido La Virginia 500g    3.450,00
Ñoquis frescos 2 x 1.200,50
Leche descremada                 1.199,99
Pan lactal integral                890,00

SUBTOTAL                         8.940,99
IVA 21%                          1.877,61
TOTAL A PAGAR              \$   10.818,60
EFECTIVO                        12.000,00
VUELTO                           1.181,40
Gracias por su compra
''';

const _ticketMexico = '''
OXXO TIENDAS
RFC OXX970814HS9
07/03/2026

Coca Cola 600ml                 25.50
Sabritas Adobadas               19.00
Bimbo Pan Blanco                48.90

SUBTOTAL                        93.40
IVA                             14.94
TOTAL                          108.34
''';

const _ticketUsa = '''
WHOLE FOODS MARKET
1234 Market St
03/15/2025

Organic Milk 2%                  5.49
Sourdough Bread                  6.99
Avocado 3 x 1.99

SUBTOTAL                        40.00
TAX                              3.20
TOTAL                           43.20
''';

void main() {
  group('parseAmount', () {
    test('formato LatAm: punto de miles, coma decimal', () {
      expect(ReceiptTextParser.parseAmount('1.234,56'), 1234.56);
      expect(ReceiptTextParser.parseAmount('10.818,60'), 10818.60);
      expect(ReceiptTextParser.parseAmount('43,20'), 43.20);
    });

    test('formato anglosajon: coma de miles, punto decimal', () {
      expect(ReceiptTextParser.parseAmount('1,234.56'), 1234.56);
      expect(ReceiptTextParser.parseAmount('43.20'), 43.20);
    });

    test('separador de miles sin decimales', () {
      expect(ReceiptTextParser.parseAmount('1.234'), 1234);
      expect(ReceiptTextParser.parseAmount('1,234'), 1234);
      expect(ReceiptTextParser.parseAmount('12.345.678'), 12345678);
    });

    test('enteros y ruido de moneda', () {
      expect(ReceiptTextParser.parseAmount('1234'), 1234);
      expect(ReceiptTextParser.parseAmount(r'$ 10.818,60'), 10818.60);
      expect(ReceiptTextParser.parseAmount(''), isNull);
      expect(ReceiptTextParser.parseAmount('abc'), isNull);
    });
  });

  group('parseAmountCents', () {
    test('devuelve centavos enteros, sin error de punto flotante', () {
      expect(ReceiptTextParser.parseAmountCents('1.234,56'), 123456);
      expect(ReceiptTextParser.parseAmountCents('1,234.56'), 123456);
      expect(ReceiptTextParser.parseAmountCents('43,20'), 4320);
      expect(ReceiptTextParser.parseAmountCents('0,01'), 1);
      expect(ReceiptTextParser.parseAmountCents('abc'), isNull);
    });
  });

  group('extractTotal', () {
    final parser = ReceiptTextParser();

    test('no confunde SUBTOTAL con TOTAL', () {
      expect(parser.extractTotal(_ticketUsa), 4320);
      expect(parser.extractTotal(_ticketMexico), 10834);
    });

    test('lee un total LatAm con miles y coma decimal', () {
      expect(parser.extractTotal(_ticketArgentina), 1081860);
    });

    test('reconoce variantes en espanol', () {
      expect(parser.extractTotal('IMPORTE TOTAL: 2.500,00'), 250000);
      expect(parser.extractTotal('NETO A PAGAR \$ 999,90'), 99990);
      expect(parser.extractTotal('TOTAL GENERAL 1.000'), 100000);
    });

    test('devuelve null cuando no hay total', () {
      expect(parser.extractTotal('COTO\nPan 100,00'), isNull);
    });

    test('regresion: el bug viejo devolvia 1.23 en vez de 1.493,82', () {
      const text = 'SUBTOTAL 1.234,56\nIVA 21%\nTOTAL \$ 1.493,82';
      expect(parser.extractTotal(text), 149382);
    });
  });

  group('extractDate', () {
    final latam = ReceiptTextParser(); // dayFirst: true
    final usa = ReceiptTextParser(dayFirst: false);

    test('fecha inequivoca DD/MM se lee bien en cualquier configuracion', () {
      expect(latam.extractDate('Fecha 25/12/2025'), DateTime(2025, 12, 25));
      expect(usa.extractDate('Fecha 25/12/2025'), DateTime(2025, 12, 25));
    });

    test('fecha inequivoca MM/DD se lee bien en cualquier configuracion', () {
      expect(latam.extractDate('Date 03/15/2025'), DateTime(2025, 3, 15));
      expect(usa.extractDate('Date 03/15/2025'), DateTime(2025, 3, 15));
    });

    test('fecha ambigua usa la preferencia del parser', () {
      expect(latam.extractDate('07/03/2026'), DateTime(2026, 3, 7));
      expect(usa.extractDate('07/03/2026'), DateTime(2026, 7, 3));
    });

    test('regresion: 13/07 ya no hace overflow al ano siguiente', () {
      // El codigo viejo hacia DateTime(2026, 13, 7) => 2027-01-07.
      expect(latam.extractDate('13/07/2026'), DateTime(2026, 7, 13));
    });

    test('formato ISO', () {
      expect(latam.extractDate('2025-11-04'), DateTime(2025, 11, 4));
    });

    test('ano de dos digitos', () {
      expect(latam.extractDate('25/12/25'), DateTime(2025, 12, 25));
    });

    test('rechaza fechas imposibles y futuras', () {
      expect(latam.extractDate('30/02/2025'), isNull);
      expect(latam.extractDate('99/99/9999'), isNull);
      final futuro = DateTime.now().add(const Duration(days: 400));
      expect(
        latam.extractDate('${futuro.day}/${futuro.month}/${futuro.year}'),
        isNull,
      );
    });

    test('sin fecha devuelve null', () {
      expect(latam.extractDate('COTO CICSA\nTOTAL 100,00'), isNull);
    });
  });

  group('cleanItemName', () {
    final parser = ReceiptTextParser();

    test('conserva tildes y enie', () {
      expect(parser.cleanItemName('Café molido'), 'Café molido');
      expect(parser.cleanItemName('Ñoquis frescos'), 'Ñoquis frescos');
      expect(parser.cleanItemName('Açaí bowl'), 'Açaí bowl');
    });

    test('limpia ruido pero mantiene simbolos utiles', () {
      expect(parser.cleanItemName('  Leche   2%  '), 'Leche 2%');
      expect(parser.cleanItemName('Pan #@!integral'), 'Pan integral');
    });
  });

  group('isTotalLine', () {
    final parser = ReceiptTextParser();

    test('filtra vocabulario en espanol', () {
      for (final line in [
        'IVA 21%',
        'EFECTIVO 12.000,00',
        'VUELTO 1.181,40',
        'SUBTOTAL 8.940,99',
        'PROPINA 500,00',
        'TARJETA DEBITO',
        'CUIT 30-54808315-6',
      ]) {
        expect(parser.isTotalLine(line), isTrue, reason: line);
      }
    });

    test('no filtra productos', () {
      expect(parser.isTotalLine('Café molido 3.450,00'), isFalse);
      expect(parser.isTotalLine('Leche descremada 1.199,99'), isFalse);
    });
  });

  group('parseItems', () {
    final parser = ReceiptTextParser();

    test('extrae items de un ticket LatAm con coma decimal', () {
      final items = parser.parseItems(_ticketArgentina);
      final nombres = items.map((i) => i.name).toList();

      expect(items, isNotEmpty, reason: 'el parser viejo devolvia 0 items');
      expect(nombres, contains('Café molido La Virginia 500g'));
      expect(nombres, contains('Leche descremada'));

      final cafe = items.firstWhere((i) => i.name.startsWith('Café'));
      expect(cafe.totalPriceCents, 345000);
    });

    test('resuelve cantidad por precio unitario', () {
      final items = parser.parseItems(_ticketArgentina);
      final noquis = items.firstWhere((i) => i.name.startsWith('Ñoquis'));
      expect(noquis.quantity, 2);
      expect(noquis.unitPriceCents, 120050);
      expect(noquis.totalPriceCents, 240100);
    });

    test('no cuenta IVA, subtotal, efectivo ni vuelto como productos', () {
      final items = parser.parseItems(_ticketArgentina);
      for (final i in items) {
        expect(
          RegExp('iva|subtotal|total|efectivo|vuelto', caseSensitive: false)
              .hasMatch(i.name),
          isFalse,
          reason: 'item indebido: ${i.name}',
        );
      }
    });

    test('sigue funcionando con tickets anglosajones', () {
      final items = parser.parseItems(_ticketUsa);
      final leche = items.firstWhere((i) => i.name.contains('Organic Milk'));
      expect(leche.totalPriceCents, 549);

      final palta = items.firstWhere((i) => i.name.contains('Avocado'));
      expect(palta.quantity, 3);
      expect(palta.unitPriceCents, 199);
    });
  });

  group('extractStoreName', () {
    final parser = ReceiptTextParser();

    test('toma el nombre del comercio y saltea CUIT/RFC/direccion', () {
      expect(parser.extractStoreName(_ticketArgentina), 'COTO CICSA');
      expect(parser.extractStoreName(_ticketMexico), 'OXXO TIENDAS');
      expect(parser.extractStoreName(_ticketUsa), 'WHOLE FOODS MARKET');
    });
  });

  group('extractCurrency', () {
    final parser = ReceiptTextParser();

    test('detecta codigos explicitos', () {
      expect(parser.extractCurrency('TOTAL ARS 1.000,00'), 'ARS');
      expect(parser.extractCurrency('TOTAL R\$ 50,00'), 'BRL');
      expect(parser.extractCurrency('TOTAL 12,00 €'), 'EUR');
    });

    test('el signo pelado es ambiguo y no se adivina', () {
      expect(parser.extractCurrency(r'TOTAL $ 1.000,00'), isNull);
    });
  });

  group('parse (integracion)', () {
    test('ticket argentino completo', () {
      final result = ReceiptTextParser().parse(_ticketArgentina);
      expect(result.storeName, 'COTO CICSA');
      expect(result.totalCents, 1081860);
      expect(result.receiptDate, DateTime(2025, 12, 25));
      expect(result.items.length, greaterThanOrEqualTo(4));
    });

    test('ticket mexicano completo', () {
      final result = ReceiptTextParser().parse(_ticketMexico);
      expect(result.storeName, 'OXXO TIENDAS');
      expect(result.totalCents, 10834);
      expect(result.receiptDate, DateTime(2026, 3, 7));
    });
  });
}
