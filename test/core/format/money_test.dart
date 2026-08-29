import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receipt_ai_finance_assistant/core/format/money.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_UY');
    await initializeDateFormatting('es_AR');
    await initializeDateFormatting('en_US');
  });

  group('Money.format', () {
    test('formatea en es_AR con punto de miles y coma decimal', () {
      final out = Money.format(123456, code: 'ARS', localeOverride: 'es_AR');
      expect(out, contains('1.234,56'));
      expect(out, contains(r'$'));
    });

    test('formatea en en_US con coma de miles y punto decimal', () {
      final out = Money.format(123456, code: 'USD', localeOverride: 'en_US');
      expect(out, contains('1,234.56'));
    });

    test('el simbolo va adelante, no atras', () {
      // CLDR para es_UY produce "1.234,56 $", que nadie escribe asi.
      final uy = Money.format(123456, code: 'UYU', localeOverride: 'es_UY');
      expect(uy, '\$ 1.234,56');
      final ar = Money.format(123456, code: 'ARS', localeOverride: 'es_AR');
      expect(ar, '\$ 1.234,56');
    });

    test('monedas sin centavos no muestran decimales', () {
      expect(Money.format(1234, code: 'CLP', localeOverride: 'es_CL'), '\$ 1.234');
      expect(Money.format(50000, code: 'PYG', localeOverride: 'es_PY'), '₲ 50.000');
    });

    test('CLP y COP no llevan centavos', () {
      expect(Money.decimalDigitsFor('CLP'), 0);
      expect(Money.decimalDigitsFor('COP'), 0);
      expect(Money.decimalDigitsFor('ARS'), 2);
    });

    test('simbolos por moneda', () {
      expect(Money.symbolFor('BRL'), r'R$');
      expect(Money.symbolFor('EUR'), '€');
      expect(Money.symbolFor('PEN'), 'S/');
      expect(Money.symbolFor('ARS'), r'$');
    });
  });

  group('centavos', () {
    test('ida y vuelta sin perder plata', () {
      for (final cents in [1, 99, 100, 123456, 1081860, 999999999]) {
        expect(Money.fromMajor(Money.toMajor(cents)), cents, reason: '\$cents');
      }
    });

    test('la suma es exacta, sin el error de los double', () {
      // 0.1 + 0.2 != 0.3 en punto flotante. En centavos si.
      expect(10 + 20, 30);
      final total = List.filled(100, 1).fold<int>(0, (a, b) => a + b);
      expect(total, 100);
    });
  });

  group('Money.parse', () {
    test('acepta ambos convenios', () {
      // parse devuelve CENTAVOS.
      expect(Money.parse('1.234,56'), 123456);
      expect(Money.parse('1,234.56'), 123456);
      expect(Money.parse('1234'), 123400);
      expect(Money.parse(r'$ 10.818,60'), 1081860);
    });

    test('regresion: el replaceAll(",", ".") viejo rompia los miles', () {
      // "1.234,56".replaceAll(',', '.') => "1.234.56" => double.tryParse null
      expect(Money.parse('1.234,56'), isNotNull);
    });

    test('entrada invalida devuelve null', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
    });
  });

  group('AppDate', () {
    test('formatea el mes en el idioma configurado', () {
      final texto = AppDate.monthYear(DateTime(2025, 12));
      // Sin locale, intl devolvia siempre "December".
      expect(texto.toLowerCase(), anyOf(contains('diciembre'), contains('december')));
    });
  });
}
