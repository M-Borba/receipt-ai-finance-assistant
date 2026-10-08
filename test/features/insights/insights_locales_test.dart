import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/insights/domain/insights_locales.dart';
import 'package:receipt_ai_finance_assistant/features/insights/domain/recordatorio_ics.dart';

var _n = 0;
ExpenseEntity _g(DateTime fecha, int cents,
        {String? store, ExpenseCategory cat = ExpenseCategory.groceries}) =>
    ExpenseEntity(
      id: 'e${_n++}',
      userId: 'u',
      category: cat,
      amountCents: cents,
      storeName: store,
      date: fecha,
      createdAt: fecha,
    );

List<String> _ids(List<dynamic> xs) => [for (final x in xs) x.id as String];

void main() {
  final hoy = DateTime(2026, 10, 10, 12);

  group('detectarFijos', () {
    List<ExpenseEntity> ute({bool esteMes = false, int dia = 15}) => [
          _g(DateTime(2026, 7, dia), 230000, store: 'UTE'),
          _g(DateTime(2026, 8, dia + 1), 250000, store: 'U.T.E.'),
          _g(DateTime(2026, 9, dia - 1), 210000, store: 'UTE'),
          if (esteMes) _g(DateTime(2026, 10, 3), 240000, store: 'UTE'),
        ];

    test('un pago por mes, los tres meses, por un monto parecido', () {
      final f = detectarFijos(gastos: ute(), hoy: hoy).single;
      expect(f.montoTipico, 230000);
      expect(f.diaTipico, 15);
      expect(f.pagadoEsteMes, isFalse);
    });

    test('sabe si ya se pago este mes', () {
      expect(detectarFijos(gastos: ute(esteMes: true), hoy: hoy).single
          .pagadoEsteMes, isTrue);
    });

    test('si falta un mes no es fijo', () {
      final g = ute()..removeAt(1);
      expect(detectarFijos(gastos: g, hoy: hoy), isEmpty);
    });

    test('el super al que vas varias veces por mes no es una factura', () {
      final g = [
        for (final m in [7, 8, 9]) ...[
          _g(DateTime(2026, m, 3), 150000, store: 'Ta-Ta'),
          _g(DateTime(2026, m, 20), 150000, store: 'Ta-Ta'),
        ],
      ];
      expect(detectarFijos(gastos: g, hoy: hoy), isEmpty);
    });

    test('montos que no se parecen no son un fijo', () {
      final g = [
        _g(DateTime(2026, 7, 5), 30000, store: 'Farmashop'),
        _g(DateTime(2026, 8, 5), 900000, store: 'Farmashop'),
        _g(DateTime(2026, 9, 5), 30000, store: 'Farmashop'),
      ];
      expect(detectarFijos(gastos: g, hoy: hoy), isEmpty);
    });
  });

  group('insightsLocales', () {
    test('sin gastos no inventa nada', () {
      expect(insightsLocales(gastos: const [], hoy: hoy, userId: 'u'), isEmpty);
    });

    test('proyeccion: 1.000 en 10 dias de un mes de 31 son 3.100', () {
      final r = insightsLocales(
        gastos: [_g(DateTime(2026, 10, 2), 100000)],
        hoy: hoy,
        userId: 'u',
      );
      final p = r.firstWhere((i) => i.id == 'local_proyeccion');
      expect(p.title, contains('3.100'));
    });

    test('antes del dia 5 no proyecta', () {
      final r = insightsLocales(
        gastos: [_g(DateTime(2026, 10, 1), 100000)],
        hoy: DateTime(2026, 10, 3),
        userId: 'u',
      );
      expect(_ids(r), isNot(contains('local_proyeccion')));
    });

    test('compara con el mes pasado A LA MISMA ALTURA, no con el mes entero',
        () {
      final r = insightsLocales(
        gastos: [
          _g(DateTime(2026, 10, 5), 200000),
          // Al dia 10 del mes pasado se habian gastado 100.000...
          _g(DateTime(2026, 9, 4), 100000),
          // ...y despues 900.000 mas, que no cuentan para "a esta altura".
          _g(DateTime(2026, 9, 25), 900000),
        ],
        hoy: hoy,
        userId: 'u',
      );
      final vs = r.firstWhere((i) => i.id == 'local_vs_anterior');
      expect(vs.title, 'Vas 100% arriba del mes pasado');
    });

    test('la categoria que mas subio, con umbral para no avisar ruido', () {
      final r = insightsLocales(
        gastos: [
          _g(DateTime(2026, 10, 4), 300000, cat: ExpenseCategory.delivery),
          _g(DateTime(2026, 9, 4), 100000, cat: ExpenseCategory.delivery),
          // Sube $10: es ruido.
          _g(DateTime(2026, 10, 4), 2000, cat: ExpenseCategory.fuel),
          _g(DateTime(2026, 9, 4), 1000, cat: ExpenseCategory.fuel),
        ],
        hoy: hoy,
        userId: 'u',
      );
      expect(_ids(r), contains('local_categoria_delivery'));
      expect(_ids(r), isNot(contains('local_categoria_fuel')));
    });

    test('comercio frecuente, sin importar como se escribio', () {
      final r = insightsLocales(
        gastos: [
          _g(DateTime(2026, 10, 1), 10000, store: 'TA-TA'),
          _g(DateTime(2026, 10, 4), 20000, store: 'Ta Ta'),
          _g(DateTime(2026, 10, 8), 30000, store: 'ta-ta'),
        ],
        hoy: hoy,
        userId: 'u',
      );
      final f = r.firstWhere((i) => i.id == 'local_frecuente');
      expect(f.title, startsWith('Fuiste 3 veces a'));
    });

    test('avisa el fijo que no aparecio, recien cerca de su dia', () {
      final g = [
        _g(DateTime(2026, 7, 12), 230000, store: 'UTE'),
        _g(DateTime(2026, 8, 12), 230000, store: 'UTE'),
        _g(DateTime(2026, 9, 12), 230000, store: 'UTE'),
      ];
      expect(_ids(insightsLocales(gastos: g, hoy: hoy, userId: 'u')),
          contains('local_fijo_ute'));
      // El dia 2 todavia falta: avisar seria ruido.
      expect(
          _ids(insightsLocales(
              gastos: g, hoy: DateTime(2026, 10, 2), userId: 'u')),
          isNot(contains('local_fijo_ute')));
    });
  });

  group('icsRecordatorio', () {
    const fijo = GastoFijo(
      clave: 'ute',
      nombre: 'UTE; luz, casa',
      montoTipico: 230000,
      diaTipico: 15,
      meses: 3,
      pagadoEsteMes: false,
    );

    test('evento mensual de dia entero con alarma, en CRLF', () {
      final ics = icsRecordatorio(fijo, hoy: hoy);
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('RRULE:FREQ=MONTHLY;BYMONTHDAY=15\r\n'));
      expect(ics, contains('DTSTART;VALUE=DATE:20261015\r\n'));
      expect(ics, contains('BEGIN:VALARM'));
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('si el dia ya paso, arranca el mes que viene', () {
      final ics = icsRecordatorio(fijo, hoy: DateTime(2026, 10, 20));
      expect(ics, contains('DTSTART;VALUE=DATE:20261115'));
    });

    test('un dia 31 se corre al 28, que existe en todos los meses', () {
      const f31 = GastoFijo(
          clave: 'alquiler',
          nombre: 'Alquiler',
          montoTipico: 2500000,
          diaTipico: 31,
          meses: 3,
          pagadoEsteMes: false);
      expect(icsRecordatorio(f31, hoy: hoy), contains('BYMONTHDAY=28'));
    });

    test('escapa comas y punto y coma del nombre', () {
      final unfolded =
          icsRecordatorio(fijo, hoy: hoy).replaceAll('\r\n ', '');
      expect(unfolded, contains(r'SUMMARY:Pagar UTE\; luz\, casa'));
    });

    test('ninguna linea pasa de 75 bytes', () {
      const largo = GastoFijo(
          clave: 'x',
          nombre: 'Administración del Edificio Rambla Gandhi número 1234 apto',
          montoTipico: 1,
          diaTipico: 1,
          meses: 3,
          pagadoEsteMes: false);
      for (final l in icsRecordatorio(largo, hoy: hoy).split('\r\n')) {
        expect(l.codeUnits.length, lessThanOrEqualTo(75), reason: l);
      }
    });
  });
}
