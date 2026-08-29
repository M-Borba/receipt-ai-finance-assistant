import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';

ExpenseEntity _gasto({String? receiptId}) => ExpenseEntity(
      id: 'e1',
      userId: 'u1',
      receiptId: receiptId,
      category: ExpenseCategory.groceries,
      amountCents: 10000,
      date: DateTime(2026, 3, 2),
      createdAt: DateTime(2026, 3, 2),
    );

void main() {
  group('isManual', () {
    test('sin receiptId es un gasto cargado a mano', () {
      expect(_gasto().isManual, isTrue);
    });

    test('con receiptId viene de un ticket escaneado', () {
      expect(_gasto(receiptId: 'r1').isManual, isFalse);
    });
  });

  test('copyWith preserva id, userId y receiptId', () {
    final original = _gasto(receiptId: 'r1');
    final editado = original.copyWith(amountCents: 25000, note: 'ajuste');

    expect(editado.amountCents, 25000);
    expect(editado.note, 'ajuste');
    expect(editado.id, 'e1');
    expect(editado.userId, 'u1');
    expect(editado.receiptId, 'r1');
    expect(editado.createdAt, original.createdAt);
  });
}
