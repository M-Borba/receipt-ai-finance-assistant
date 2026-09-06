import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/balance.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/entities/group_expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/split.dart';

GroupExpenseEntity gasto({
  required int total,
  required Map<String, int> pago,
  required Map<String, int> reparto,
  String id = 'g1',
}) {
  return GroupExpenseEntity(
    id: id,
    groupId: 'grupo',
    description: 'gasto',
    amountCents: total,
    date: DateTime(2026, 8, 29),
    mode: SplitMode.equal,
    paidBy: pago,
    shares: reparto,
    createdBy: 'ana',
    createdAt: DateTime(2026, 8, 29),
  );
}

void main() {
  group('netBalances', () {
    test('la suma de todos los balances es cero', () {
      final libro = [
        gasto(
            total: 10000,
            pago: {'ana': 10000},
            reparto: {'ana': 3334, 'juan': 3333, 'yo': 3333},
            id: 'a'),
        gasto(
            total: 4500,
            pago: {'juan': 4500},
            reparto: {'ana': 1500, 'juan': 1500, 'yo': 1500},
            id: 'b'),
      ];
      final neto = netBalances(libro);
      expect(neto.values.fold<int>(0, (a, b) => a + b), 0);
      expect(neto['ana'], 10000 - 3334 - 1500);
      expect(neto['yo'], -(3333 + 1500));
    });

    test('quien quedo en cero no aparece', () {
      final libro = [
        gasto(total: 1000, pago: {'ana': 1000}, reparto: {'ana': 1000}),
      ];
      expect(netBalances(libro), isEmpty);
    });

    test('un libro vacio no debe nada', () {
      expect(netBalances([]), isEmpty);
    });
  });

  group('pairwiseDebts', () {
    test('el caso simple: uno paga, todos deben', () {
      final libro = [
        gasto(
            total: 9000,
            pago: {'ana': 9000},
            reparto: {'ana': 3000, 'juan': 3000, 'yo': 3000}),
      ];
      expect(pairwiseDebts(libro), [
        const Debt(from: 'juan', to: 'ana', cents: 3000),
        const Debt(from: 'yo', to: 'ana', cents: 3000),
      ]);
    });

    test('deudas opuestas se netean en vez de acumularse', () {
      // Ana pone una, Juan pone la otra. No se deben 3000 cada uno: se deben
      // la diferencia. Es lo que hace que la vista sea legible.
      final libro = [
        gasto(
            total: 6000,
            pago: {'ana': 6000},
            reparto: {'ana': 3000, 'juan': 3000},
            id: 'a'),
        gasto(
            total: 4000,
            pago: {'juan': 4000},
            reparto: {'ana': 2000, 'juan': 2000},
            id: 'b'),
      ];
      expect(pairwiseDebts(libro), [
        const Debt(from: 'juan', to: 'ana', cents: 1000),
      ]);
    });

    test('cuando queda todo saldado no hay ninguna deuda', () {
      final libro = [
        gasto(
            total: 5000,
            pago: {'ana': 5000},
            reparto: {'ana': 2500, 'juan': 2500},
            id: 'a'),
        gasto(
            total: 5000,
            pago: {'juan': 5000},
            reparto: {'ana': 2500, 'juan': 2500},
            id: 'b'),
      ];
      expect(pairwiseDebts(libro), isEmpty);
    });

    test('quien pago justo lo que le tocaba no es acreedor de nadie', () {
      // Yo puse 2500 y me tocaban 2500: no puse plata de nadie mas, asi que
      // Juan no me debe nada. Le debe todo a Ana, que si puso de mas.
      final libro = [
        gasto(
          total: 10000,
          pago: {'ana': 7500, 'yo': 2500},
          reparto: {'ana': 2500, 'juan': 2500, 'yo': 2500, 'zoe': 2500},
        ),
      ];
      final deJuan = pairwiseDebts(libro).where((d) => d.from == 'juan');
      expect(deJuan, [const Debt(from: 'juan', to: 'ana', cents: 2500)]);
    });

    test('con dos acreedores, la deuda se reparte proporcionalmente', () {
      // Ana puso de mas 5500 y yo 500. Juan debe 3000 y los reparte entre los
      // dos en proporcion a lo que cada uno adelanto.
      final libro = [
        gasto(
          total: 10000,
          pago: {'ana': 7500, 'yo': 2500},
          reparto: {'ana': 2000, 'yo': 2000, 'juan': 3000, 'zoe': 3000},
        ),
      ];
      final deJuan = pairwiseDebts(libro).where((d) => d.from == 'juan');
      expect(deJuan.length, 2);
      expect(deJuan.fold<int>(0, (a, d) => a + d.cents), 3000);
      expect(deJuan.firstWhere((d) => d.to == 'ana').cents, 2750);
      expect(deJuan.firstWhere((d) => d.to == 'yo').cents, 250);
    });

    test('las deudas suman lo mismo que los balances netos', () {
      // Invariante fuerte: la vista de a pares no puede inventar ni perder
      // plata respecto del neto.
      final libro = [
        gasto(
            total: 10001,
            pago: {'ana': 10001},
            reparto: {'ana': 3334, 'juan': 3334, 'yo': 3333},
            id: 'a'),
        gasto(
            total: 777,
            pago: {'yo': 500, 'juan': 277},
            reparto: {'ana': 259, 'juan': 259, 'yo': 259},
            id: 'b'),
      ];
      final neto = netBalances(libro);
      final deudas = pairwiseDebts(libro);

      final desdeDeudas = <String, int>{};
      for (final d in deudas) {
        desdeDeudas[d.from] = (desdeDeudas[d.from] ?? 0) - d.cents;
        desdeDeudas[d.to] = (desdeDeudas[d.to] ?? 0) + d.cents;
      }
      desdeDeudas.removeWhere((_, v) => v == 0);
      expect(desdeDeudas, neto);
    });

    test('el orden es determinista, no depende del orden del Map', () {
      final libro = [
        gasto(
          total: 3000,
          pago: {'zoe': 3000},
          reparto: {'zoe': 1000, 'ana': 1000, 'juan': 1000},
        ),
      ];
      final a = pairwiseDebts(libro);
      final b = pairwiseDebts(libro.reversed);
      expect(a, b);
      expect(a.map((d) => d.from), ['ana', 'juan']);
    });
  });

  group('debtsInvolving', () {
    test('muestra solo lo de esa persona', () {
      final libro = [
        gasto(
          total: 9000,
          pago: {'ana': 9000},
          reparto: {'ana': 3000, 'juan': 3000, 'yo': 3000},
        ),
      ];
      expect(debtsInvolving(libro, 'yo'),
          [const Debt(from: 'yo', to: 'ana', cents: 3000)]);
      expect(debtsInvolving(libro, 'ana').length, 2);
    });
  });

  group('isBalanced', () {
    test('detecta un gasto donde lo repartido no suma el total', () {
      expect(
        gasto(total: 1000, pago: {'ana': 1000}, reparto: {'ana': 999})
            .isBalanced,
        isFalse,
      );
      expect(
        gasto(total: 1000, pago: {'ana': 1000}, reparto: {'ana': 1000})
            .isBalanced,
        isTrue,
      );
    });
  });
}
