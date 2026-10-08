import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/split.dart';

ItemAsignado _item(int cents, [List<String> quienes = const []]) =>
    (cents: cents, quienes: quienes);

void main() {
  const todos = ['ana', 'juan', 'yo'];

  group('splitByItems', () {
    test('cada uno paga lo suyo cuando los items suman el total', () {
      final r = splitByItems(
        totalCents: 100000,
        participants: todos,
        items: [
          _item(40000, ['ana']),
          _item(60000, ['juan', 'yo']),
        ],
      );
      expect(r, {'ana': 40000, 'juan': 30000, 'yo': 30000});
    });

    test('un item sin nadie elegido es de todos', () {
      final r = splitByItems(
        totalCents: 90000,
        participants: todos,
        items: [_item(90000)],
      );
      expect(r, {'ana': 30000, 'juan': 30000, 'yo': 30000});
    });

    test('la propina se reparte en proporcion a lo que consumio cada uno', () {
      // Items por 1.000, se pago 1.100 con el 10%.
      final r = splitByItems(
        totalCents: 110000,
        participants: todos,
        items: [
          _item(80000, ['ana']),
          _item(20000, ['yo']),
        ],
      );
      expect(r, {'ana': 88000, 'yo': 22000});
      expect(r.containsKey('juan'), isFalse,
          reason: 'Juan no consumio nada: no paga ni la propina');
    });

    test('si el OCR leyo los items de mas, el total real manda', () {
      final r = splitByItems(
        totalCents: 105600,
        participants: ['ana', 'yo'],
        items: [_item(66621, ['ana']), _item(66621, ['yo'])],
      );
      expect(r.values.reduce((a, b) => a + b), 105600);
      expect(r['ana'], r['yo']);
    });

    test('los items en cero o negativos no rompen nada', () {
      final r = splitByItems(
        totalCents: 10000,
        participants: ['ana', 'yo'],
        items: [_item(10031, ['ana']), _item(-31), _item(0, ['yo'])],
      );
      expect(r, {'ana': 10000});
    });

    test('sin items con monto es partes iguales', () {
      final r = splitByItems(
        totalCents: 10001,
        participants: todos,
        items: const [],
      );
      expect(r.values.reduce((a, b) => a + b), 10001);
      expect(r.length, 3);
    });

    test('alguien que no participa del gasto no recibe items', () {
      final r = splitByItems(
        totalCents: 5000,
        participants: ['ana', 'yo'],
        items: [_item(5000, ['juan'])],
      );
      // Juan no esta en el gasto: el item cae a "entre todos".
      expect(r, {'ana': 2500, 'yo': 2500});
    });

    test('barrido al azar: siempre suma el total y nunca da negativos', () {
      final rnd = Random(7);
      for (var caso = 0; caso < 3000; caso++) {
        final gente = ['a', 'b', 'c', 'd', 'e'].sublist(0, 1 + rnd.nextInt(5));
        final items = [
          for (var i = 0; i < rnd.nextInt(12); i++)
            _item(rnd.nextInt(200000) - 1000, [
              for (final p in gente)
                if (rnd.nextBool()) p
            ]),
        ];
        final total = 1 + rnd.nextInt(2000000);
        final r = splitByItems(
            totalCents: total, participants: gente, items: items);
        expect(r.values.fold<int>(0, (a, b) => a + b), total,
            reason: 'caso $caso');
        expect(r.values.every((v) => v > 0), isTrue, reason: 'caso $caso');
      }
    });
  });
}
