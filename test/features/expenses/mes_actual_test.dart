import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/presentation/providers/mes_actual_provider.dart';

void main() {
  group('MesActual.mesDe', () {
    test('recorta al primer instante del mes', () {
      expect(MesActual.mesDe(DateTime(2026, 8, 31, 23, 59, 59)),
          DateTime(2026, 8));
      expect(MesActual.mesDe(DateTime(2026, 9, 1, 0, 0, 1)), DateTime(2026, 9));
    });

    test('dos momentos del mismo mes dan el mismo valor', () {
      // Es lo que permite comparar por igualdad y no refrescar de gusto.
      expect(MesActual.mesDe(DateTime(2026, 8, 1)),
          MesActual.mesDe(DateTime(2026, 8, 30, 18, 45)));
    });

    test('el cambio de mes cambia el valor', () {
      // El bug: el 1 de septiembre a la mañana, con la pestaña abierta desde el
      // 31, se veía el total de agosto bajo el título "septiembre".
      expect(MesActual.mesDe(DateTime(2026, 8, 31, 23, 59)),
          isNot(MesActual.mesDe(DateTime(2026, 9, 1, 0, 1))));
    });

    test('diciembre a enero cruza el año', () {
      // `DateTime(año, 13)` normaliza a enero del siguiente, así que el timer
      // no necesita un caso especial para diciembre.
      expect(DateTime(2026, 12 + 1), DateTime(2027, 1));
      expect(MesActual.mesDe(DateTime(2026, 12, 31, 23, 59)),
          DateTime(2026, 12));
    });
  });
}
