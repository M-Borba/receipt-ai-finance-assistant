import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/expense_entity.dart';

abstract interface class ExpenseRepository {
  /// Gastos de los ultimos [windowMonths] meses, mas nuevos primero.
  Stream<List<ExpenseEntity>> watchExpenses({int windowMonths});

  /// Carga un gasto a mano, sin ticket.
  Future<Either<Failure, ExpenseEntity>> addManualExpense({
    required int amountCents,
    required ExpenseCategory category,
    required DateTime date,
    String? storeName,
    String? note,
  });

  Future<Either<Failure, ExpenseEntity>> updateExpense(ExpenseEntity expense);

  Future<Either<Failure, void>> deleteExpense(String id);

  /// Todos los gastos del usuario, para exportar.
  Future<Either<Failure, List<ExpenseEntity>>> getAllExpenses();
}
