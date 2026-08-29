import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/budgets/domain/entities/budget_entity.dart';
import 'package:receipt_ai_finance_assistant/features/budgets/domain/entities/budget_status.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';

BudgetStatus _status({required int limit, required int spent}) => BudgetStatus(
      category: ExpenseCategory.groceries,
      limitCents: limit,
      spentCents: spent,
    );

void main() {
  group('estados', () {
    test('por debajo del 80% esta ok', () {
      expect(_status(limit: 1500000, spent: 840000).state, BudgetState.ok);
      expect(_status(limit: 1000, spent: 0).state, BudgetState.ok);
    });

    test('justo en el 80% ya avisa', () {
      expect(_status(limit: 1000, spent: 800).state, BudgetState.warning);
    });

    test('entre 80% y 100% avisa pero no se paso', () {
      final s = _status(limit: 1000, spent: 999);
      expect(s.state, BudgetState.warning);
      expect(s.isExceeded, isFalse);
    });

    test('justo en el tope todavia no se paso', () {
      final s = _status(limit: 1000, spent: 1000);
      expect(s.isExceeded, isFalse);
      expect(s.state, BudgetState.warning);
    });

    test('un centavo mas ya es exceso', () {
      final s = _status(limit: 1000, spent: 1001);
      expect(s.isExceeded, isTrue);
      expect(s.state, BudgetState.exceeded);
    });
  });

  group('numeros', () {
    test('porcentaje y restante', () {
      final s = _status(limit: 1500000, spent: 840000);
      expect(s.percent, 56);
      expect(s.remainingCents, 660000);
    });

    test('excedido: el restante es negativo y el porcentaje pasa de 100', () {
      final s = _status(limit: 1000, spent: 1500);
      expect(s.percent, 150);
      expect(s.remainingCents, -500);
    });

    test('la barra de progreso nunca pasa de 1', () {
      expect(_status(limit: 1000, spent: 5000).clampedRatio, 1.0);
      expect(_status(limit: 1000, spent: 250).clampedRatio, 0.25);
    });

    test('tope 0 no divide por cero', () {
      final s = _status(limit: 0, spent: 500);
      expect(s.ratio, 0);
      expect(s.percent, 0);
      expect(s.clampedRatio, 0);
    });

    test('sin gastos, todo en cero', () {
      final s = _status(limit: 1000, spent: 0);
      expect(s.percent, 0);
      expect(s.remainingCents, 1000);
      expect(s.isExceeded, isFalse);
    });
  });

  test('from arma el estado desde el presupuesto', () {
    const budget = BudgetEntity(
      id: 'b1',
      userId: 'u1',
      category: ExpenseCategory.delivery,
      limitCents: 500000,
    );
    final s = BudgetStatus.from(budget, 450000);
    expect(s.category, ExpenseCategory.delivery);
    expect(s.limitCents, 500000);
    expect(s.spentCents, 450000);
    expect(s.state, BudgetState.warning);
  });
}
