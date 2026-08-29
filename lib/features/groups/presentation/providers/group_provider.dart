import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/repositories/group_repository.dart';
import '../../domain/balance.dart';
import '../../domain/entities/group_entity.dart';
import '../../domain/entities/group_expense_entity.dart';

part 'group_provider.g.dart';

@riverpod
Stream<List<GroupEntity>> groups(Ref ref) =>
    ref.watch(groupRepositoryProvider).watchGroups();

@riverpod
Stream<GroupEntity?> group(Ref ref, String groupId) =>
    ref.watch(groupRepositoryProvider).watchGroup(groupId);

@riverpod
Stream<List<GroupExpenseEntity>> groupExpenses(Ref ref, String groupId) =>
    ref.watch(groupRepositoryProvider).watchExpenses(groupId);

/// Las deudas de a pares del grupo, derivadas del libro.
///
/// Se calculan aca y no se guardan: dos personas cargando un gasto al mismo
/// tiempo se pisarian un balance guardado.
@riverpod
List<Debt> groupDebts(Ref ref, String groupId) {
  final gastos = ref.watch(groupExpensesProvider(groupId)).value ?? const [];
  return pairwiseDebts(gastos);
}

/// Cuanto me deben (positivo) o debo (negativo) en este grupo.
@riverpod
int myBalance(Ref ref, String groupId) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return 0;
  final gastos = ref.watch(groupExpensesProvider(groupId)).value ?? const [];
  return balanceOf(gastos, uid);
}
