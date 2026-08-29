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
}
