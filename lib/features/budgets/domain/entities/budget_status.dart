import 'package:equatable/equatable.dart';

import '../../../expenses/domain/entities/expense_entity.dart';
import 'budget_entity.dart';

enum BudgetState {
  /// Por debajo del umbral de aviso.
  ok,

  /// Llego al 80% del tope: todavia no se paso, pero conviene mirarlo.
  warning,

  /// Se paso del tope.
  exceeded,
}

/// Cuanto se gasto contra el tope, ya resuelto.
///
/// Es lo que convierte un numero suelto en un juicio: "$8.400 en supermercado"
/// no significa nada; "$8.400 de $15.000" si.
class BudgetStatus extends Equatable {
  /// A partir de este porcentaje se avisa.
  static const warningRatio = 0.8;

  final ExpenseCategory category;
  final int limitCents;
  final int spentCents;

  const BudgetStatus({
    required this.category,
    required this.limitCents,
    required this.spentCents,
  });

  factory BudgetStatus.from(BudgetEntity budget, int spentCents) {
    return BudgetStatus(
      category: budget.category,
      limitCents: budget.limitCents,
      spentCents: spentCents,
    );
  }

  /// Proporcion gastada. Puede pasar de 1.0 cuando te excediste.
  /// Con tope 0 devuelve 0 en vez de dividir por cero.
  double get ratio => limitCents <= 0 ? 0 : spentCents / limitCents;

  /// Para barras de progreso, que no aceptan mas de 1.
  double get clampedRatio => ratio.clamp(0.0, 1.0);

  int get percent => (ratio * 100).round();

  /// Cuanto queda. Negativo si te pasaste.
  int get remainingCents => limitCents - spentCents;

  bool get isExceeded => spentCents > limitCents;

  BudgetState get state {
    if (isExceeded) return BudgetState.exceeded;
    if (ratio >= warningRatio) return BudgetState.warning;
    return BudgetState.ok;
  }

  @override
  List<Object?> get props => [category, limitCents, spentCents];
}
