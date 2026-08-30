import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/core/errors/failures.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/entities/expense_entity.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/domain/repositories/expense_repository.dart';
import 'package:receipt_ai_finance_assistant/features/expenses/presentation/providers/expense_provider.dart';

/// Repositorio que siempre falla, para probar que el fallo se reporta.
class _RepoQueFalla implements ExpenseRepository {
  const _RepoQueFalla();

  static const mensaje = 'Firestore rechazo la escritura';

  @override
  Stream<List<ExpenseEntity>> watchExpenses({int windowMonths = 12}) =>
      Stream.value(const []);

  @override
  Future<Either<Failure, ExpenseEntity>> addManualExpense({
    required int amountCents,
    required ExpenseCategory category,
    required DateTime date,
    String? storeName,
    String? note,
  }) async {
    // Un tick de demora: sin esto la pantalla nunca llega a cerrarse antes de
    // que termine la escritura, que es justo el escenario del bug.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const Left(NetworkFailure(mensaje));
  }

  @override
  Future<Either<Failure, ExpenseEntity>> updateExpense(ExpenseEntity e) async =>
      const Left(NetworkFailure(mensaje));

  @override
  Future<Either<Failure, void>> deleteExpense(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const Left(NetworkFailure(mensaje));
  }

  @override
  Future<Either<Failure, List<ExpenseEntity>>> getAllExpenses() async =>
      const Right([]);
}

void main() {
  ProviderContainer contenedor() => ProviderContainer(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(const _RepoQueFalla()),
        ],
      );

  group('ExpenseActions: un fallo nunca se reporta como exito', () {
    test('addManual devuelve el mensaje cuando la escritura falla', () async {
      final c = contenedor();
      addTearDown(c.dispose);

      final r = await c.read(expenseActionsProvider.notifier).addManual(
            amountCents: 125000,
            category: ExpenseCategory.groceries,
            date: DateTime(2026, 8, 30),
          );

      // En el contrato de este metodo, null significa EXITO.
      expect(r, isNotNull);
      expect(r, _RepoQueFalla.mensaje);
    });

    test(
        'sigue devolviendo el error aunque el provider se descarte durante la '
        'escritura', () async {
      // El bug: habia un `if (!ref.mounted) return null` ANTES de mirar el
      // resultado. Si la persona cargaba un gasto y navegaba afuera, una
      // escritura fallida devolvia null, o sea "se guardo", y el gasto se
      // perdia sin que nada avisara.
      final c = contenedor();
      final futuro = c.read(expenseActionsProvider.notifier).addManual(
            amountCents: 125000,
            category: ExpenseCategory.groceries,
            date: DateTime(2026, 8, 30),
          );

      // Se cierra la pantalla mientras la escritura sigue en vuelo.
      c.dispose();

      expect(await futuro, _RepoQueFalla.mensaje,
          reason: 'perder un gasto en silencio es peor que mostrar un error');
    });

    test('delete tambien reporta el fallo si el provider ya se descarto',
        () async {
      final c = contenedor();
      final futuro = c.read(expenseActionsProvider.notifier).delete('abc');
      c.dispose();
      expect(await futuro, _RepoQueFalla.mensaje);
    });
  });
}
