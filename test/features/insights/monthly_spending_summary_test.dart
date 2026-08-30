import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/insights/domain/entities/monthly_spending_summary.dart';

ExpenseEntity _gasto({
  required int amountCents,
  required DateTime date,
  ExpenseCategory category = ExpenseCategory.groceries,
  String? store,
  String id = 'e1',
}) {
  return ExpenseEntity(
    id: id,
    userId: 'u1',
    receiptId: 'r1',
    category: category,
    amountCents: amountCents,
    storeName: store,
    date: date,
    createdAt: date,
  );
}

void main() {
  final mes = DateTime(2026, 3);

  group('MonthlySpendingSummary.from', () {
    test('agrega solo los gastos del mes pedido', () {
      final resumen = MonthlySpendingSummary.from([
        _gasto(amountCents: 10000, date: DateTime(2026, 3, 2), id: 'a'),
        _gasto(amountCents: 5000, date: DateTime(2026, 3, 20), id: 'b'),
        _gasto(amountCents: 99900, date: DateTime(2026, 2, 28), id: 'c'),
      ], mes);

      expect(resumen.totalCents, 15000);
      expect(resumen.expenseCount, 2);
    });

    test('los comercios top son del mes, no de todo el historico', () {
      final resumen = MonthlySpendingSummary.from([
        _gasto(amountCents: 10000, date: DateTime(2026, 3, 2), store: 'Coto', id: 'a'),
        _gasto(amountCents: 4000, date: DateTime(2026, 3, 9), store: 'Coto', id: 'b'),
        _gasto(amountCents: 50000, date: DateTime(2025, 1, 5), store: 'Jumbo', id: 'c'),
      ], mes);

      expect(resumen.topMerchants.map((m) => m.name), ['Coto']);
      expect(resumen.topMerchants.first.totalCents, 14000);
      expect(resumen.topMerchants.first.visits, 2);
    });

    test('suma por categoria', () {
      final resumen = MonthlySpendingSummary.from([
        _gasto(amountCents: 10000, date: DateTime(2026, 3, 2), id: 'a'),
        _gasto(
          amountCents: 3000,
          date: DateTime(2026, 3, 3),
          category: ExpenseCategory.delivery,
          id: 'b',
        ),
      ], mes);

      expect(resumen.categoryTotals[ExpenseCategory.groceries], 10000);
      expect(resumen.categoryTotals[ExpenseCategory.delivery], 3000);
    });

    test('un mes sin gastos queda vacio', () {
      expect(MonthlySpendingSummary.from([], mes).isEmpty, isTrue);
    });
  });

  group('igualdad por valor', () {
    test('dos resumenes con los mismos numeros son iguales', () {
      final gastos = [
        _gasto(amountCents: 10000, date: DateTime(2026, 3, 2), store: 'Coto', id: 'a'),
        _gasto(amountCents: 4000, date: DateTime(2026, 3, 9), store: 'Dia', id: 'b'),
      ];

      // Este es el test que importa: cada snapshot de Firestore produce listas
      // nuevas. Si los resumenes no fueran iguales, el provider de insights se
      // invalidaria y dispararia otra llamada (pagada) al modelo.
      final a = MonthlySpendingSummary.from(gastos, mes);
      final b = MonthlySpendingSummary.from(List.of(gastos), mes);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('un gasto nuevo si cambia la igualdad', () {
      final a = MonthlySpendingSummary.from(
        [_gasto(amountCents: 10000, date: DateTime(2026, 3, 2), id: 'a')],
        mes,
      );
      final b = MonthlySpendingSummary.from(
        [
          _gasto(amountCents: 10000, date: DateTime(2026, 3, 2), id: 'a'),
          _gasto(amountCents: 500, date: DateTime(2026, 3, 4), id: 'b'),
        ],
        mes,
      );

      expect(a, isNot(equals(b)));
    });
  });

  group('MerchantTotal.signature (regresion)', () {
    test('interpola de verdad, no devuelve una constante', () {
      const a = MerchantTotal(name: 'Tienda Inglesa', totalCents: 105600, visits: 3);
      const b = MerchantTotal(name: 'Devoto', totalCents: 42000, visits: 1);
      // Tenia los `$` escapados y devolvia el texto literal
      // "$name:$totalCents:$visits" para TODOS los comercios.
      expect(a.signature, isNot(b.signature));
      expect(a.signature, contains('Tienda Inglesa'));
      expect(a.signature, contains('105600'));
      expect(a.signature, isNot(contains(r'$name')));
    });

    test('dos resumenes con comercios distintos NO son iguales', () {
      // Es el punto de toda la clase: si comparan iguales, los insights no se
      // regeneran y quedan mostrando datos viejos.
      MonthlySpendingSummary conComercio(String nombre, int cents) =>
          MonthlySpendingSummary(
            month: DateTime(2026, 8),
            totalCents: 200000,
            expenseCount: 5,
            categoryTotals: const {},
            topMerchants: [
              MerchantTotal(name: nombre, totalCents: cents, visits: 2),
            ],
          );
      expect(conComercio('Devoto', 100000) == conComercio('Ta-Ta', 100000), isFalse);
      expect(conComercio('Devoto', 100000) == conComercio('Devoto', 999), isFalse);
      expect(conComercio('Devoto', 100000) == conComercio('Devoto', 100000), isTrue);
    });
  });
}
