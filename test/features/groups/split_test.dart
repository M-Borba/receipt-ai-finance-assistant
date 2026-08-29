import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/groups/domain/split.dart';

void main() {
  group('splitLargestRemainder', () {
    test('la invariante: siempre suma exactamente el total', () {
      // El caso que motiva todo el modulo: 100 entre 3 da 33,33 y tres veces
      // eso son 99,99. Un centavo perdido por gasto y el grupo no cierra.
      expect(splitLargestRemainder(10000, [1, 1, 1]), [3334, 3333, 3333]);
      expect(splitLargestRemainder(10000, [1, 1, 1]).fold<int>(0, (a, b) => a + b),
          10000);
    });

    test('la invariante aguanta cualquier total y cualquier reparto', () {
      // Barrido chico pero exhaustivo: si hay un total y unos pesos donde se
      // pierde o se inventa un centavo, esto lo encuentra.
      for (var total = 0; total <= 400; total++) {
        for (final pesos in const [
          [1, 1],
          [1, 1, 1],
          [1, 1, 1, 1, 1, 1, 1],
          [4, 1, 1],
          [2, 3, 5, 7, 11],
          [1, 0, 1],
          [999, 1],
        ]) {
          final r = splitLargestRemainder(total, pesos);
          expect(r.fold<int>(0, (a, b) => a + b), total,
              reason: 'total=$total pesos=$pesos dio $r');
          expect(r.length, pesos.length);
          expect(r.every((c) => c >= 0), isTrue, reason: 'total=$total $pesos');
        }
      }
    });

    test('el caso que pidio el usuario: 2/3 y 1/6 cada uno, sin fracciones', () {
      // "yo puedo pagar 2 tercios y mis amigos 1 sexto cada uno"
      final r = splitLargestRemainder(60000, [4, 1, 1]);
      expect(r, [40000, 10000, 10000]);
      // Y con un total que no divide redondo sigue cerrando.
      final feo = splitLargestRemainder(10001, [4, 1, 1]);
      expect(feo.fold<int>(0, (a, b) => a + b), 10001);
    });

    test('los centavos sobrantes van a los restos mas grandes', () {
      // 10 centavos entre pesos 1 y 2: 3,33 y 6,66. El centavo va al resto
      // mayor, que es el del peso 2.
      expect(splitLargestRemainder(10, [1, 2]), [3, 7]);
    });

    test('desempate por indice: dos dispositivos calculan lo mismo', () {
      // Restos identicos: el centavo tiene que ir siempre al primero.
      for (var i = 0; i < 50; i++) {
        expect(splitLargestRemainder(100, [1, 1, 1]), [34, 33, 33]);
      }
    });

    test('un peso en cero no recibe nada', () {
      expect(splitLargestRemainder(1000, [1, 0, 1]), [500, 0, 500]);
    });

    test('todos los pesos en cero devuelve todo cero, no divide por cero', () {
      expect(splitLargestRemainder(1000, [0, 0]), [0, 0]);
    });

    test('lista vacia devuelve lista vacia', () {
      expect(splitLargestRemainder(1000, []), isEmpty);
    });

    test('un total negativo (una devolucion) tambien cierra exacto', () {
      final r = splitLargestRemainder(-10000, [1, 1, 1]);
      expect(r.fold<int>(0, (a, b) => a + b), -10000);
    });

    test('pesos negativos no tienen sentido y se rechazan', () {
      expect(() => splitLargestRemainder(100, [1, -1]), throwsArgumentError);
    });
  });

  group('computeShares', () {
    const gente = ['ana', 'juan', 'yo'];

    test('partes iguales', () {
      final s = computeShares(
          totalCents: 10000, participants: gente, mode: SplitMode.equal);
      expect(s.values.fold<int>(0, (a, b) => a + b), 10000);
      expect(s['ana'], 3334);
    });

    test('por partes: yo consumi mas', () {
      final s = computeShares(
        totalCents: 60000,
        participants: gente,
        mode: SplitMode.shares,
        inputs: {'yo': 4, 'ana': 1, 'juan': 1},
      );
      expect(s, {'ana': 10000, 'juan': 10000, 'yo': 40000});
    });

    test('a quien no se le asigna parte se le asigna cero', () {
      final s = computeShares(
        totalCents: 1000,
        participants: gente,
        mode: SplitMode.shares,
        inputs: {'yo': 1, 'ana': 1},
      );
      expect(s['juan'], 0);
      expect(s.values.fold<int>(0, (a, b) => a + b), 1000);
    });

    test('por partes con todo en cero se rechaza', () {
      expect(
        () => computeShares(
            totalCents: 1000,
            participants: gente,
            mode: SplitMode.shares,
            inputs: {}),
        throwsArgumentError,
      );
    });

    test('porcentajes en centesimas, y el redondeo no pierde centavos', () {
      final s = computeShares(
        totalCents: 10000,
        participants: gente,
        mode: SplitMode.percentage,
        inputs: {'ana': 3333, 'juan': 3333, 'yo': 3334},
      );
      expect(s.values.fold<int>(0, (a, b) => a + b), 10000);
    });

    test('porcentajes que no suman 100 se rechazan', () {
      expect(
        () => computeShares(
          totalCents: 10000,
          participants: gente,
          mode: SplitMode.percentage,
          inputs: {'ana': 5000, 'juan': 4000, 'yo': 0},
        ),
        throwsArgumentError,
      );
    });

    test('montos exactos que no suman el total se rechazan', () {
      // Dejar pasar esto es el bug que hace que el grupo no llegue a cero.
      expect(
        () => computeShares(
          totalCents: 10000,
          participants: gente,
          mode: SplitMode.exact,
          inputs: {'ana': 5000, 'juan': 4000, 'yo': 0},
        ),
        throwsArgumentError,
      );
    });

    test('montos exactos que cierran se aceptan tal cual', () {
      final s = computeShares(
        totalCents: 10000,
        participants: gente,
        mode: SplitMode.exact,
        inputs: {'ana': 5000, 'juan': 4000, 'yo': 1000},
      );
      expect(s, {'ana': 5000, 'juan': 4000, 'yo': 1000});
    });

    test('participantes repetidos se rechazan', () {
      expect(
        () => computeShares(
            totalCents: 100,
            participants: ['ana', 'ana'],
            mode: SplitMode.equal),
        throwsArgumentError,
      );
    });
  });
}
