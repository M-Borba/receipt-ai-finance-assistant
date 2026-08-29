import 'package:equatable/equatable.dart';

import '../../../expenses/domain/entities/expense_entity.dart';

/// Tope mensual de gasto para una categoria.
///
/// Se repite todos los meses: no hay topes distintos por mes ni historial.
/// Es deliberado, cubre casi todos los casos con la mitad del trabajo.
class BudgetEntity extends Equatable {
  final String id;
  final String userId;
  final ExpenseCategory category;

  /// En centavos. Ver [Money].
  final int limitCents;

  const BudgetEntity({
    required this.id,
    required this.userId,
    required this.category,
    required this.limitCents,
  });

  BudgetEntity copyWith({int? limitCents}) => BudgetEntity(
        id: id,
        userId: userId,
        category: category,
        limitCents: limitCents ?? this.limitCents,
      );

  @override
  List<Object?> get props => [id, userId, category, limitCents];
}
