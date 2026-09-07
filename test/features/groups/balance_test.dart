import 'dart:math';

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

  group('pairwiseDebts con varios pagadores Y varios deudores', () {
    // El bug D21 necesita las dos cosas a la vez: con un solo deudor o un solo
    // acreedor las cuentas cerraban igual, y por eso los tests viejos pasaban.
    test('dos deudores y dos acreedores de un centavo cada uno', () {
      // Ana y Zoe pusieron 1 centavo de mas cada una. Juan y Beto deben 1
      // centavo cada uno. Repartiendo fila por fila, los dos deudores le daban
      // su centavo al MISMO acreedor: uno cobraba 2 y el otro nada.
      final libro = [
        gasto(
          total: 4,
          pago: {'ana': 2, 'zoe': 2},
          reparto: {'ana': 1, 'zoe': 1, 'juan': 1, 'beto': 1},
        ),
      ];
      final cobra = <String, int>{};
      for (final d in pairwiseDebts(libro)) {
        cobra[d.to] = (cobra[d.to] ?? 0) + d.cents;
      }
      expect(cobra, {'ana': 1, 'zoe': 1});
    });

    test('las deudas siguen sumando el neto con la matriz completa', () {
      final libro = [
        gasto(
          total: 10000,
          pago: {'ana': 3333, 'zoe': 6667},
          reparto: {'ana': 2500, 'zoe': 2500, 'juan': 2500, 'beto': 2500},
          id: 'a',
        ),
        gasto(
          total: 777,
          pago: {'juan': 389, 'beto': 388},
          reparto: {'ana': 194, 'zoe': 194, 'juan': 194, 'beto': 195},
          id: 'b',
        ),
      ];
      final neto = netBalances(libro);
      final desdeDeudas = <String, int>{};
      for (final d in pairwiseDebts(libro)) {
        desdeDeudas[d.from] = (desdeDeudas[d.from] ?? 0) - d.cents;
        desdeDeudas[d.to] = (desdeDeudas[d.to] ?? 0) + d.cents;
      }
      desdeDeudas.removeWhere((_, v) => v == 0);
      expect(desdeDeudas, neto);
    });
  });

  group('allocateDebtsToCredits', () {
    List<int> sumasFila(List<List<int>> m) =>
        [for (final f in m) f.fold<int>(0, (a, b) => a + b)];

    List<int> sumasColumna(List<List<int>> m, int cols) => [
          for (var c = 0; c < cols; c++)
            m.fold<int>(0, (a, f) => a + f[c]),
        ];

    test('las dos margenes cierran exactamente en todos los casos chicos', () {
      // Barrido exhaustivo: todas las particiones de un total hasta 10, de un
      // lado y del otro. Es el invariante que rompia el reparto fila por fila.
      List<List<int>> particiones(int total, int piezas) {
        if (piezas == 1) return [[total]];
        final salida = <List<int>>[];
        for (var primero = 1; primero <= total - (piezas - 1); primero++) {
          for (final resto in particiones(total - primero, piezas - 1)) {
            salida.add([primero, ...resto]);
          }
        }
        return salida;
      }

      var casos = 0;
      for (var total = 1; total <= 10; total++) {
        for (var nd = 1; nd <= 3; nd++) {
          for (var nc = 1; nc <= 3; nc++) {
            if (nd > total || nc > total) continue;
            for (final deudas in particiones(total, nd)) {
              for (final creditos in particiones(total, nc)) {
                final m = allocateDebtsToCredits(deudas, creditos);
                casos++;
                expect(sumasFila(m), deudas,
                    reason: 'filas: deudas=$deudas creditos=$creditos -> $m');
                expect(sumasColumna(m, nc), creditos,
                    reason: 'columnas: deudas=$deudas creditos=$creditos -> $m');
                for (final f in m) {
                  for (final v in f) {
                    expect(v, greaterThanOrEqualTo(0),
                        reason: 'negativo: deudas=$deudas creditos=$creditos');
                  }
                }
              }
            }
          }
        }
      }
      expect(casos, greaterThan(2000));
    });

    test('las dos margenes cierran con montos y grupos grandes', () {
      // Semilla fija: si algun dia falla, falla igual en todas las maquinas.
      final rnd = Random(20260906);
      for (var caso = 0; caso < 3000; caso++) {
        final nd = 1 + rnd.nextInt(6);
        final nc = 1 + rnd.nextInt(6);
        final piezas = nd > nc ? nd : nc;
        final total = piezas + rnd.nextInt(500000);

        List<int> repartir(int n) {
          final pesos = [for (var i = 0; i < n; i++) 1 + rnd.nextInt(50)];
          final partes = splitLargestRemainder(total, pesos);
          // Nadie puede quedar en cero: un acreedor de cero no es acreedor.
          for (var i = 0; i < n; i++) {
            if (partes[i] == 0) {
              final mayor = partes.indexOf(partes.reduce((a, b) => a > b ? a : b));
              partes[mayor] -= 1;
              partes[i] += 1;
            }
          }
          return partes;
        }

        final deudas = repartir(nd);
        final creditos = repartir(nc);
        final m = allocateDebtsToCredits(deudas, creditos);
        expect(sumasFila(m), deudas, reason: 'filas caso $caso');
        expect(sumasColumna(m, nc), creditos, reason: 'columnas caso $caso');
        for (final f in m) {
          for (final v in f) {
            expect(v, greaterThanOrEqualTo(0), reason: 'negativo caso $caso');
          }
        }
      }
    });

    test('reparte en proporcion a lo que puso cada acreedor', () {
      final m = allocateDebtsToCredits([3000], [5500, 500]);
      expect(m, [[2750, 250]]);
    });

    test('un gasto descuadrado no inventa deuda: reparte lo que se puede', () {
      // Se debe 1000 en total pero los acreedores solo pusieron 600 de mas.
      // Las dos margenes no pueden cerrar porque no suman lo mismo.
      final m = allocateDebtsToCredits([600, 400], [300, 300]);
      expect(sumasColumna(m, 2), [300, 300], reason: 'no cobra mas de su credito');
      for (var f = 0; f < 2; f++) {
        expect(sumasFila(m)[f], lessThanOrEqualTo([600, 400][f]));
      }
      for (final f in m) {
        for (final v in f) {
          expect(v, greaterThanOrEqualTo(0));
        }
      }
    });

    test('listas vacias y todo en cero no revientan', () {
      expect(allocateDebtsToCredits([], [100]), isEmpty);
      expect(allocateDebtsToCredits([100], []), [<int>[]]);
      expect(allocateDebtsToCredits([0, 0], [0]), [[0], [0]]);
    });

    test('una magnitud negativa es un error de programacion, no un dato', () {
      expect(() => allocateDebtsToCredits([-1], [1]), throwsArgumentError);
      expect(() => allocateDebtsToCredits([1], [-1]), throwsArgumentError);
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
