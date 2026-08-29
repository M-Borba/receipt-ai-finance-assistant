import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../entities/budget_entity.dart';

abstract interface class BudgetRepository {
  Stream<List<BudgetEntity>> watchBudgets();

  /// Crea o actualiza el tope de una categoria. Un tope por categoria.
  Future<Either<Failure, BudgetEntity>> setBudget({
    required ExpenseCategory category,
    required int limitCents,
  });

  /// Borra por categoria: el id es determinista (userId_categoria), asi que
  /// no hace falta que quien llama lo conozca ni lo reconstruya.
  Future<Either<Failure, void>> removeBudget(ExpenseCategory category);
}
