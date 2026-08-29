import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../expenses/domain/entities/expense_entity.dart';
import '../../../expenses/presentation/providers/expense_provider.dart';
import '../../data/repositories/budget_repository_impl.dart';
import '../../domain/entities/budget_entity.dart';
import '../../domain/entities/budget_status.dart';

part 'budget_provider.g.dart';

@riverpod
Stream<List<BudgetEntity>> budgetsStream(Ref ref) {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return Stream.value(const []);
  return ref.watch(budgetRepositoryProvider).watchBudgets();
}

/// Cruza los topes con lo gastado este mes.
///
/// Ordenado con lo mas urgente arriba: primero lo excedido, despues lo que
/// esta cerca del tope.
@riverpod
List<BudgetStatus> budgetStatuses(Ref ref) {
  final budgets = ref.watch(budgetsStreamProvider).value ?? const [];
  if (budgets.isEmpty) return const [];

  final gastado = ref.watch(categoryTotalsCurrentMonthProvider);

  final estados = budgets
      .map((b) => BudgetStatus.from(b, gastado[b.category] ?? 0))
      .toList()
    ..sort((a, b) => b.ratio.compareTo(a.ratio));

  return estados;
}

/// Tope de una categoria puntual, o null si no tiene.
@riverpod
BudgetStatus? budgetStatusFor(Ref ref, ExpenseCategory category) {
  for (final s in ref.watch(budgetStatusesProvider)) {
    if (s.category == category) return s;
  }
  return null;
}

/// Cuantos presupuestos estan en verde, para el resumen del dashboard.
@riverpod
({int ok, int total, int exceeded}) budgetSummary(Ref ref) {
  final estados = ref.watch(budgetStatusesProvider);
  return (
    ok: estados.where((s) => s.state == BudgetState.ok).length,
    total: estados.length,
    exceeded: estados.where((s) => s.state == BudgetState.exceeded).length,
  );
}

@riverpod
class BudgetActions extends _$BudgetActions {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Devuelve null si salio bien, o el mensaje de error.
  Future<String?> setBudget(ExpenseCategory category, int limitCents) async {
    final result = await ref
        .read(budgetRepositoryProvider)
        .setBudget(category: category, limitCents: limitCents);
    return result.fold((f) => f.message, (_) => null);
  }

  Future<String?> remove(ExpenseCategory category) async {
    final result = await ref.read(budgetRepositoryProvider).removeBudget(category);
    return result.fold((f) => f.message, (_) => null);
  }
}
